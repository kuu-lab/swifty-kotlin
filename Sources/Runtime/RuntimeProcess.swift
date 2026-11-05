import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// `RuntimeProcessPipeOutputSink.write(_:)` shadows the POSIX `write(2)`
/// symbol inside the type, so pipe writes go through this qualified wrapper.
private func runtimePosixWrite(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
        return _DarwinFoundation3.write(fd, buffer, count)
    #elseif canImport(Glibc)
        return Glibc.write(fd, buffer, count)
    #else
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: runtimePosixWrite unsupported platform")
    #endif
}

/// Input stream reading the read end of a child-process pipe (the child's
/// stdout or stderr). Reads go straight to the kernel `read(2)` so a blocked
/// child keeps the parent parked exactly like a JVM `ProcessPipeInputStream`;
/// `readChunk` performs a single underlying read per call, matching
/// `InputStream.read(byte[])` semantics for blocking streams.
private final class RuntimeProcessPipeInputStreamBox: RuntimeInputStreamBox, RuntimeChunkedInputStream {
    private let fileHandle: FileHandle
    private let fd: Int32
    private var streamClosed = false
    private var reachedEOF = false
    private var failure: String?

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.fd = fileHandle.fileDescriptor
        super.init(data: Data())
    }

    override var readError: String? { failure }

    override func readByte() -> Int {
        failure = nil
        guard !streamClosed, !reachedEOF else { return -1 }
        var byte: UInt8 = 0
        while true {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            let count = withUnsafeMutableBytes(of: &byte) { read(fd, $0.baseAddress, 1) }
            let readErrno = errno
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            if count == 1 { return Int(byte) }
            if count == 0 {
                reachedEOF = true
                return -1
            }
            if readErrno == EINTR { continue }
            failure = String(cString: strerror(readErrno))
            return -1
        }
    }

    /// One `read(2)` per call: a blocking pipe must not loop for more data
    /// after the first successful read — JVM `read(byte[])` returns whatever a
    /// single read yields (at least one byte, or -1 at EOF/error).
    func readChunk(_ maxCount: Int) -> [Int] {
        guard !streamClosed, !reachedEOF, maxCount > 0 else { return [] }
        var chunk = [UInt8](repeating: 0, count: maxCount)
        while true {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            let readErrno = errno
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            if count > 0 {
                return (0 ..< count).map { Int(Int8(bitPattern: chunk[$0])) }
            }
            if count == 0 {
                reachedEOF = true
                return []
            }
            if readErrno == EINTR { continue }
            failure = String(cString: strerror(readErrno))
            return []
        }
    }

    /// `FIONREAD` is not exposed to Swift on Darwin; report unknown like the
    /// socket input stream does. Blocking reads still observe every byte.
    override func available() -> Int {
        0
    }

    override func skip(_ count: Int) -> Int {
        var skipped = 0
        var scratch: UInt8 = 0
        while skipped < max(0, count) {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            let n = withUnsafeMutableBytes(of: &scratch) { read(fd, $0.baseAddress, 1) }
            let readErrno = errno
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            if n > 0 {
                skipped += 1
                continue
            }
            if n == 0 {
                reachedEOF = true
                break
            }
            if readErrno == EINTR { continue }
            failure = String(cString: strerror(readErrno))
            break
        }
        return skipped
    }

    override func readAllBytes() -> [Int] {
        var bytes: [Int] = []
        while true {
            let chunk = readChunk(8192)
            if chunk.isEmpty { break }
            bytes.append(contentsOf: chunk)
        }
        return bytes
    }

    override func close() {
        guard !streamClosed else { return }
        streamClosed = true
        reachedEOF = true
        try? fileHandle.close()
    }

    deinit {
        close()
    }
}

/// Output sink writing to the write end of the child-stdin pipe. Writes loop
/// on `write(2)` until the buffer is drained so large Kotlin writes are not
/// truncated by a partial pipe write.
private final class RuntimeProcessPipeOutputSink: RuntimeOutputStreamSink {
    private let fileHandle: FileHandle
    private let fd: Int32
    private var closed = false

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.fd = fileHandle.fileDescriptor
    }

    func write(_ data: Data) throws {
        guard !closed else {
            throw RuntimeKotlinThrownError(thrownRaw: runtimeAllocateIOException(message: "Stream closed"))
        }
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
                let count = runtimePosixWrite(fd, baseAddress.advanced(by: sent), data.count - sent)
                let writeErrno = errno
                if gcBlocking { runtimeGCSafepoints.endBlocking() }
                if count > 0 {
                    sent += count
                    continue
                }
                if writeErrno == EINTR { continue }
                if writeErrno == EPIPE {
                    throw RuntimeKotlinThrownError(thrownRaw: runtimeAllocateIOException(message: "Broken pipe"))
                }
                throw RuntimeKotlinThrownError(
                    thrownRaw: runtimeAllocateIOException(message: String(cString: strerror(writeErrno)))
                )
            }
        }
    }

    /// Pipe writes are unbuffered kernel hand-offs; there is nothing to flush.
    func flush() throws {}

    func close() {
        guard !closed else { return }
        closed = true
        try? fileHandle.close()
    }

    func closeThrowing() throws {
        guard !closed else { return }
        closed = true
        try fileHandle.close()
    }
}

/// JDK `ProcessBuilder.NullOutputStream`: every non-empty write fails with
/// `IOException("Stream closed")`; `flush()`/`close()` are no-ops.
private final class RuntimeNullOutputStreamSink: RuntimeOutputStreamSink {
    func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        throw RuntimeKotlinThrownError(thrownRaw: runtimeAllocateIOException(message: "Stream closed"))
    }

    func flush() throws {}
    func close() {}
    func closeThrowing() throws {}
}

/// One stream's redirection target, decoded from the `ProcessBuilder` spec
/// strings passed to `__kk_process_start_full`.
private enum RuntimeProcessRedirectKind {
    case pipe
    case inherit
    case discard
    case fileRead
    case fileWrite
    case fileAppend
}

private struct RuntimeProcessRedirectSpec {
    var kind: RuntimeProcessRedirectKind
    var path: String?
}

/// Parses `"P"`/`"I"`/`"D"` or `kind + path` (`R`/`W`/`A`); returns nil on
/// malformed input so the spawn fails instead of silently mis-wiring I/O.
private func runtimeParseRedirectSpec(_ spec: String) -> RuntimeProcessRedirectSpec? {
    guard let kindChar = spec.first else { return nil }
    let path = spec.count > 1 ? String(spec.dropFirst()) : nil
    switch kindChar {
    case "P": return RuntimeProcessRedirectSpec(kind: .pipe, path: nil)
    case "I": return RuntimeProcessRedirectSpec(kind: .inherit, path: nil)
    case "D": return RuntimeProcessRedirectSpec(kind: .discard, path: nil)
    case "R": return path.map { RuntimeProcessRedirectSpec(kind: .fileRead, path: $0) }
    case "W": return path.map { RuntimeProcessRedirectSpec(kind: .fileWrite, path: $0) }
    case "A": return path.map { RuntimeProcessRedirectSpec(kind: .fileAppend, path: $0) }
    default: return nil
    }
}

/// Opens `path` for child stdio redirection. `writing` selects
/// `O_WRONLY|O_CREAT` with `O_TRUNC` or `O_APPEND`; reads use `O_RDONLY`.
/// The returned handle owns the descriptor (`closeOnDealloc`).
private func runtimeOpenProcessRedirectFile(path: String, writing: Bool, append: Bool) -> FileHandle? {
    let flags: Int32
    if writing {
        flags = O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC)
    } else {
        flags = O_RDONLY
    }
    let fd = open(path, flags, 0o666)
    guard fd >= 0 else { return nil }
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}

private func runtimeOpenDevNull(writing: Bool) -> FileHandle? {
    let fd = open("/dev/null", writing ? O_WRONLY : O_RDONLY)
    guard fd >= 0 else { return nil }
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}

/// Tracks one spawned child: exit status (published by a monitor thread that
/// reaps the process exactly once), the optional parent-held pipe ends, and
/// the lazy stream boxes exposed through `Process.getXStream()`.
final class RuntimeProcessBox: @unchecked Sendable {
    let process: Foundation.Process
    let pid: pid_t
    /// Parent-held pipe ends; each is non-nil exactly when that stream was
    /// redirected to `PIPE`. The child-side ends were closed right after
    /// `run()` so reads observe EOF when the child exits.
    let stdinPipe: Pipe?
    let stdoutPipe: Pipe?
    let stderrPipe: Pipe?

    private let exitLock = NSCondition()
    private var exited = false
    private var exitStatus = 0
    private var exitMonitorStarted = false

    private let streamLock = NSLock()
    private var inputStreamBox: RuntimeInputStreamBox?
    private var outputStreamBox: RuntimeOutputStreamBox?
    private var errorStreamBox: RuntimeInputStreamBox?
    private var nullInputStreamBox: RuntimeInputStreamBox?
    private var nullOutputStreamBox: RuntimeOutputStreamBox?
    private var inputStreamRawValue = 0
    private var outputStreamRawValue = 0
    private var errorStreamRawValue = 0
    private var nullInputStreamRawValue = 0
    private var nullOutputStreamRawValue = 0

    init(process: Foundation.Process, pid: pid_t, stdinPipe: Pipe?, stdoutPipe: Pipe?, stderrPipe: Pipe?) {
        self.process = process
        self.pid = pid
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    /// Spawns a daemon thread that reaps the child exactly once and publishes
    /// its decoded exit status (128+signal for signal deaths, matching the
    /// JDK's `exitValue()` for `kill -TERM`/`kill -KILL` children).
    func startExitMonitor(registry: RuntimeProcessRegistry) {
        exitLock.lock()
        if exitMonitorStarted {
            exitLock.unlock()
            return
        }
        exitMonitorStarted = true
        exitLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            self.process.waitUntilExit()
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            let status: Int
            if self.process.terminationReason == .uncaughtSignal {
                status = 128 + Int(self.process.terminationStatus)
            } else {
                status = Int(self.process.terminationStatus)
            }
            self.markExited(status: status)
            registry.removePidMapping(pid: self.pid, box: self)
        }
    }

    private func markExited(status: Int) {
        exitLock.lock()
        exited = true
        exitStatus = status
        exitLock.broadcast()
        exitLock.unlock()
    }

    /// Blocks until the monitor publishes the exit status.
    func waitFor() -> Int {
        exitLock.lock()
        while !exited {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            exitLock.wait()
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
        }
        let status = exitStatus
        exitLock.unlock()
        return status
    }

    /// Non-blocking check followed by a timed wait on the exit condition.
    /// `timeoutNanos <= 0` polls once, matching `Process.waitFor(long, unit)`
    /// for non-positive timeouts.
    func waitFor(timeoutNanos: Int64) -> Bool {
        exitLock.lock()
        defer { exitLock.unlock() }
        var remainingNanos = timeoutNanos
        let startUptime = DispatchTime.now().uptimeNanoseconds
        while !exited {
            if remainingNanos <= 0 { return false }
            // NSCondition.wait(until:) takes a wall-clock Date; cap each slice
            // so a huge timeout still re-checks `exited` periodically and the
            // monotonic uptime delta drives the real deadline.
            let slice = min(remainingNanos, 3_600_000_000_000)
            let deadline = Date(timeIntervalSinceNow: Double(slice) / 1_000_000_000.0)
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            _ = exitLock.wait(until: deadline)
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            if exited { break }
            let elapsed = Int64(DispatchTime.now().uptimeNanoseconds &- startUptime)
            remainingNanos = timeoutNanos &- elapsed
        }
        return exited
    }

    /// `Int32.min` while running so Kotlin maps it to
    /// `IllegalThreadStateException`. The sentinel must fit the Kotlin `Int`
    /// return slot: `Int.min` (Int64.min) truncates to 0 across the ABI.
    func exitValue() -> Int {
        exitLock.lock()
        defer { exitLock.unlock() }
        return exited ? exitStatus : Int(Int32.min)
    }

    var isExited: Bool {
        exitLock.lock()
        defer { exitLock.unlock() }
        return exited
    }

    func destroy() {
        if process.isRunning {
            process.terminate()
        }
    }

    func destroyForcibly() {
        if process.isRunning {
            kill(pid, SIGKILL)
        }
    }

    /// Shared `NullInputStream` for both non-piped readable streams; the JDK
    /// returns the same singleton for `getInputStream()`/`getErrorStream()`
    /// under non-PIPE redirects, so reference equality holds here too.
    private func sharedNullInputStreamRaw() -> Int {
        if nullInputStreamRawValue != 0 { return nullInputStreamRawValue }
        let box = RuntimeInputStreamBox(data: Data())
        nullInputStreamBox = box
        nullInputStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.InputStream", input: true)
        return nullInputStreamRawValue
    }

    private func sharedNullOutputStreamRaw() -> Int {
        if nullOutputStreamRawValue != 0 { return nullOutputStreamRawValue }
        let box = RuntimeOutputStreamBox(sink: RuntimeNullOutputStreamSink())
        nullOutputStreamBox = box
        nullOutputStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.OutputStream", input: false)
        return nullOutputStreamRawValue
    }

    /// `Process.getInputStream()`: the child's stdout, or a null stream when
    /// stdout was redirected away from a pipe.
    func inputStreamRaw() -> Int {
        streamLock.lock()
        defer { streamLock.unlock() }
        if inputStreamRawValue != 0 { return inputStreamRawValue }
        if let stdoutPipe {
            let box = RuntimeProcessPipeInputStreamBox(fileHandle: stdoutPipe.fileHandleForReading)
            inputStreamBox = box
            inputStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.InputStream", input: true)
        } else {
            inputStreamRawValue = sharedNullInputStreamRaw()
        }
        return inputStreamRawValue
    }

    /// `Process.getOutputStream()`: the child's stdin, or a null output stream
    /// when stdin was redirected away from a pipe.
    func outputStreamRaw() -> Int {
        streamLock.lock()
        defer { streamLock.unlock() }
        if outputStreamRawValue != 0 { return outputStreamRawValue }
        if let stdinPipe {
            let box = RuntimeOutputStreamBox(sink: RuntimeProcessPipeOutputSink(fileHandle: stdinPipe.fileHandleForWriting))
            outputStreamBox = box
            outputStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.OutputStream", input: false)
        } else {
            outputStreamRawValue = sharedNullOutputStreamRaw()
        }
        return outputStreamRawValue
    }

    /// `Process.getErrorStream()`: the child's stderr, a null stream under
    /// `redirectErrorStream(true)`, or a null stream for non-PIPE redirects.
    func errorStreamRaw() -> Int {
        streamLock.lock()
        defer { streamLock.unlock() }
        if errorStreamRawValue != 0 { return errorStreamRawValue }
        if let stderrPipe {
            let box = RuntimeProcessPipeInputStreamBox(fileHandle: stderrPipe.fileHandleForReading)
            errorStreamBox = box
            errorStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.InputStream", input: true)
        } else {
            errorStreamRawValue = sharedNullInputStreamRaw()
        }
        return errorStreamRawValue
    }
}

final class RuntimeProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextHandle = 1
    private var processes: [Int: RuntimeProcessBox] = [:]
    /// Live registry children by PID so `ProcessHandle.isAlive`/`of` can
    /// distinguish our (reaped-once) children from foreign processes. Entries
    /// are removed when the exit monitor publishes the status, so a recycled
    /// PID correctly falls through to the `kill(pid, 0)` probe.
    private var byPid: [pid_t: RuntimeProcessBox] = [:]

    func insert(_ box: RuntimeProcessBox) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let handle = nextHandle
        nextHandle += 1
        processes[handle] = box
        byPid[box.pid] = box
        return handle
    }

    func process(for handle: Int) -> RuntimeProcessBox? {
        lock.lock()
        defer { lock.unlock() }
        return processes[handle]
    }

    func box(forPid pid: pid_t) -> RuntimeProcessBox? {
        lock.lock()
        defer { lock.unlock() }
        return byPid[pid]
    }

    func removePidMapping(pid: pid_t, box: RuntimeProcessBox) {
        lock.lock()
        defer { lock.unlock() }
        if byPid[pid] === box {
            byPid.removeValue(forKey: pid)
        }
    }
}

let runtimeProcessRegistry = RuntimeProcessRegistry()

private func runtimeProcessExecutablePath(_ name: String) -> String? {
    let fileManager = FileManager.default
    if name.contains("/") {
        return fileManager.isExecutableFile(atPath: name) ? name : nil
    }

    let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    for directory in searchPath.split(separator: ":", omittingEmptySubsequences: false) {
        let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
            .appendingPathComponent(name)
            .path
        if fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

/// `envp == nil` inherits the parent environment; a non-nil array fully
/// replaces it, matching `Runtime.exec(cmd, envp, dir)` on the JDK. Entries
/// are `KEY=VALUE` strings; an entry without `=` maps to an empty value.
private func runtimeProcessEnvironment(_ envp: [String]?) -> [String: String]? {
    guard let envp else { return nil }
    var environment: [String: String] = [:]
    environment.reserveCapacity(envp.count)
    for entry in envp {
        if let separator = entry.firstIndex(of: "=") {
            environment[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        } else {
            environment[entry] = ""
        }
    }
    return environment
}

/// Spawns `command` (NUL-joined argv produced by `ProcessBuilder`/`Runtime.exec`)
/// with stdin/stdout/stderr wired per `redirects` (`nil` means all-PIPE, the
/// `Runtime.exec`/`__kk_process_start` behavior). `mergeErrorStream` dups the
/// child's stderr onto its stdout target, matching
/// `ProcessBuilder.redirectErrorStream(true)`.
private func runtimeProcessSpawn(
    commandRaw: Int,
    envp: [String]?,
    dirPath: String?,
    redirects: [RuntimeProcessRedirectSpec]?,
    mergeErrorStream: Bool
) -> Int {
    guard let command = runtimeStringFromRaw(commandRaw) else { return 0 }
    let arguments = command.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
    guard let executable = arguments.first,
          !executable.isEmpty,
          let executablePath = runtimeProcessExecutablePath(executable)
    else { return 0 }

    let stdinSpec = redirects?[0] ?? RuntimeProcessRedirectSpec(kind: .pipe, path: nil)
    let stdoutSpec = redirects?[1] ?? RuntimeProcessRedirectSpec(kind: .pipe, path: nil)
    let stderrSpec = redirects?[2] ?? RuntimeProcessRedirectSpec(kind: .pipe, path: nil)

    let process = Foundation.Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = Array(arguments.dropFirst())
    if let environment = runtimeProcessEnvironment(envp) {
        process.environment = environment
    }
    if let dirPath, !dirPath.isEmpty {
        process.currentDirectoryURL = URL(fileURLWithPath: dirPath)
    }

    var stdinPipe: Pipe?
    var stdoutPipe: Pipe?
    var stderrPipe: Pipe?
    var ownedHandles: [FileHandle] = []

    // --- stdin ---
    switch stdinSpec.kind {
    case .pipe:
        let pipe = Pipe()
        stdinPipe = pipe
        process.standardInput = pipe.fileHandleForReading
    case .inherit:
        process.standardInput = FileHandle.standardInput
    case .discard:
        guard let handle = runtimeOpenDevNull(writing: false) else { return 0 }
        ownedHandles.append(handle)
        process.standardInput = handle
    case .fileRead:
        guard let path = stdinSpec.path,
              let handle = runtimeOpenProcessRedirectFile(path: path, writing: false, append: false)
        else { return 0 }
        ownedHandles.append(handle)
        process.standardInput = handle
    case .fileWrite, .fileAppend:
        return 0  // invalid redirect for stdin; Kotlin validates earlier
    }

    // --- stdout ---
    switch stdoutSpec.kind {
    case .pipe:
        let pipe = Pipe()
        stdoutPipe = pipe
        process.standardOutput = pipe.fileHandleForWriting
    case .inherit:
        process.standardOutput = FileHandle.standardOutput
    case .discard:
        guard let handle = runtimeOpenDevNull(writing: true) else { return 0 }
        ownedHandles.append(handle)
        process.standardOutput = handle
    case .fileWrite, .fileAppend:
        guard let path = stdoutSpec.path,
              let handle = runtimeOpenProcessRedirectFile(path: path, writing: true, append: stdoutSpec.kind == .fileAppend)
        else { return 0 }
        ownedHandles.append(handle)
        process.standardOutput = handle
    case .fileRead:
        return 0
    }

    // --- stderr ---
    if mergeErrorStream {
        // JDK: child fd2 is dup'd onto fd1's target. Reusing the same
        // FileHandle instance gives identical semantics for pipes, files,
        // inherit, and discard.
        process.standardError = process.standardOutput
    } else {
        switch stderrSpec.kind {
        case .pipe:
            let pipe = Pipe()
            stderrPipe = pipe
            process.standardError = pipe.fileHandleForWriting
        case .inherit:
            process.standardError = FileHandle.standardError
        case .discard:
            guard let handle = runtimeOpenDevNull(writing: true) else { return 0 }
            ownedHandles.append(handle)
            process.standardError = handle
        case .fileWrite, .fileAppend:
            guard let path = stderrSpec.path,
                  let handle = runtimeOpenProcessRedirectFile(path: path, writing: true, append: stderrSpec.kind == .fileAppend)
            else { return 0 }
            ownedHandles.append(handle)
            process.standardError = handle
        case .fileRead:
            return 0
        }
    }

    // `Swift.print` buffers through libc stdout; flush all stdio streams
    // before spawn so INHERIT-redirected children cannot overtake buffered
    // parent output on the shared descriptor, matching JVM println ordering.
    // `fflush(nil)` is used instead of `stdout`/`stderr` because Glibc's
    // FILE* globals are not concurrency-safe under Swift 6.
    fflush(nil)

    do {
        try process.run()
    } catch {
        // The child never started; release every descriptor we opened so
        // nothing leaks.
        for pipe in [stdinPipe, stdoutPipe, stderrPipe].compactMap({ $0 }) {
            for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
                try? handle.close()
            }
        }
        for handle in ownedHandles {
            try? handle.close()
        }
        return 0
    }

    // The child owns its dup'd descriptors now. Closing the parent's copies
    // of the child-side ends keeps the descriptor table clean and — for the
    // stdout/stderr write ends — is what lets parent reads observe EOF once
    // the child exits. `ownedHandles` are the parent's copies of redirect
    // files/devnull (never the inherited standard handles).
    try? stdinPipe?.fileHandleForReading.close()
    try? stdoutPipe?.fileHandleForWriting.close()
    try? stderrPipe?.fileHandleForWriting.close()
    for handle in ownedHandles {
        try? handle.close()
    }

    let box = RuntimeProcessBox(
        process: process,
        pid: pid_t(process.processIdentifier),
        stdinPipe: stdinPipe,
        stdoutPipe: stdoutPipe,
        stderrPipe: stderrPipe
    )
    let handle = runtimeProcessRegistry.insert(box)
    box.startExitMonitor(registry: runtimeProcessRegistry)
    return handle
}

@_cdecl("__kk_process_current_pid")
public func __kk_process_current_pid() -> Int {
    Int(getpid())
}

@_cdecl("__kk_process_start")
public func __kk_process_start(_ commandRaw: Int) -> Int {
    runtimeProcessSpawn(commandRaw: commandRaw, envp: nil, dirPath: nil, redirects: nil, mergeErrorStream: false)
}

/// `Runtime.exec` envp/dir overloads: `commandRaw` keeps the NUL-joined argv
/// encoding of `__kk_process_start`; `envpRaw` is a nullable `Array<String>`
/// of `KEY=VALUE` entries (null sentinel inherits the parent environment) and
/// `dirRaw` a nullable working-directory path (null sentinel inherits the
/// parent's current directory).
@_cdecl("__kk_process_start_ex")
public func __kk_process_start_ex(_ commandRaw: Int, _ envpRaw: Int, _ dirRaw: Int) -> Int {
    var envp: [String]? = nil
    if envpRaw != runtimeNullSentinelInt,
       let array = runtimeArrayBox(from: envpRaw)
    {
        envp = array.elements.compactMap { runtimeStringFromRaw($0) }
    }
    return runtimeProcessSpawn(
        commandRaw: commandRaw,
        envp: envp,
        dirPath: runtimeStringFromRaw(dirRaw),
        redirects: nil,
        mergeErrorStream: false
    )
}

/// `ProcessBuilder.start()` full form: `redirectsRaw` is a 3-element
/// `Array<String>` of stream specs (stdin/stdout/stderr, each `"P"`/`"I"`/`"D"`
/// or a kind letter plus path); `errorStreamRaw` nonzero merges stderr into
/// stdout.
@_cdecl("__kk_process_start_full")
public func __kk_process_start_full(_ commandRaw: Int, _ envpRaw: Int, _ dirRaw: Int, _ redirectsRaw: Int, _ errorStreamRaw: Int) -> Int {
    var envp: [String]? = nil
    if envpRaw != runtimeNullSentinelInt,
       let array = runtimeArrayBox(from: envpRaw)
    {
        envp = array.elements.compactMap { runtimeStringFromRaw($0) }
    }
    var redirects: [RuntimeProcessRedirectSpec]? = nil
    if redirectsRaw != runtimeNullSentinelInt,
       let array = runtimeArrayBox(from: redirectsRaw)
    {
        var parsed: [RuntimeProcessRedirectSpec] = []
        parsed.reserveCapacity(3)
        for element in array.elements {
            guard let specString = runtimeStringFromRaw(element),
                  let spec = runtimeParseRedirectSpec(specString)
            else { return 0 }
            parsed.append(spec)
        }
        guard parsed.count == 3 else { return 0 }
        redirects = parsed
    }
    return runtimeProcessSpawn(
        commandRaw: commandRaw,
        envp: envp,
        dirPath: runtimeStringFromRaw(dirRaw),
        redirects: redirects,
        mergeErrorStream: errorStreamRaw != 0
    )
}

@_cdecl("__kk_process_wait_for")
public func __kk_process_wait_for(_ handle: Int) -> Int {
    runtimeProcessRegistry.process(for: handle)?.waitFor() ?? -1
}

@_cdecl("__kk_process_wait_for_timeout")
public func __kk_process_wait_for_timeout(_ handle: Int, _ timeoutNanos: Int) -> Int {
    guard let box = runtimeProcessRegistry.process(for: handle) else { return 0 }
    return box.waitFor(timeoutNanos: Int64(timeoutNanos)) ? 1 : 0
}

@_cdecl("__kk_process_exit_value")
public func __kk_process_exit_value(_ handle: Int) -> Int {
    runtimeProcessRegistry.process(for: handle)?.exitValue() ?? Int(Int32.min)
}

@_cdecl("__kk_process_is_alive")
public func __kk_process_is_alive(_ handle: Int) -> Int {
    guard let box = runtimeProcessRegistry.process(for: handle) else { return 0 }
    return box.isExited ? 0 : 1
}

@_cdecl("__kk_process_pid")
public func __kk_process_pid(_ handle: Int) -> Int {
    guard let box = runtimeProcessRegistry.process(for: handle) else { return 0 }
    return Int(box.pid)
}

@_cdecl("__kk_process_destroy")
public func __kk_process_destroy(_ handle: Int) {
    runtimeProcessRegistry.process(for: handle)?.destroy()
}

@_cdecl("__kk_process_destroy_forcibly")
public func __kk_process_destroy_forcibly(_ handle: Int) {
    runtimeProcessRegistry.process(for: handle)?.destroyForcibly()
}

@_cdecl("__kk_process_input_stream")
public func __kk_process_input_stream(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let process = runtimeProcessRegistry.process(for: handle) else {
        outThrown?.pointee = runtimeAllocateIOException(message: "No such process")
        return 0
    }
    return process.inputStreamRaw()
}

@_cdecl("__kk_process_output_stream")
public func __kk_process_output_stream(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let process = runtimeProcessRegistry.process(for: handle) else {
        outThrown?.pointee = runtimeAllocateIOException(message: "No such process")
        return 0
    }
    return process.outputStreamRaw()
}

@_cdecl("__kk_process_error_stream")
public func __kk_process_error_stream(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let process = runtimeProcessRegistry.process(for: handle) else {
        outThrown?.pointee = runtimeAllocateIOException(message: "No such process")
        return 0
    }
    return process.errorStreamRaw()
}
