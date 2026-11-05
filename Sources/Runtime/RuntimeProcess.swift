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

private final class RuntimeProcessBox: @unchecked Sendable {
    let process: Foundation.Process
    /// Parent-held pipe ends. `stdinPipe.fileHandleForWriting` feeds the
    /// child's stdin; `stdoutPipe`/`stderrPipe.fileHandleForReading` drain the
    /// child's stdout/stderr. The child-side ends were closed right after
    /// `run()` so reads observe EOF when the child exits.
    let stdinPipe: Pipe
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
    private let streamLock = NSLock()
    private var inputStreamBox: RuntimeProcessPipeInputStreamBox?
    private var outputStreamBox: RuntimeOutputStreamBox?
    private var errorStreamBox: RuntimeProcessPipeInputStreamBox?
    private var inputStreamRawValue = 0
    private var outputStreamRawValue = 0
    private var errorStreamRawValue = 0

    init(_ process: Foundation.Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    func waitFor() -> Int {
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        process.waitUntilExit()
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        return Int(process.terminationStatus)
    }

    func exitValue() -> Int {
        process.isRunning ? Int.min : Int(process.terminationStatus)
    }

    func destroy() {
        if process.isRunning {
            process.terminate()
        }
    }

    /// `Process.getInputStream()`: the child's stdout, readable by the parent.
    /// The same stream object is returned on repeated calls, matching the JDK.
    func inputStreamRaw() -> Int {
        streamLock.lock()
        defer { streamLock.unlock() }
        if inputStreamRawValue != 0 { return inputStreamRawValue }
        let box = RuntimeProcessPipeInputStreamBox(fileHandle: stdoutPipe.fileHandleForReading)
        inputStreamBox = box
        inputStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.InputStream", input: true)
        return inputStreamRawValue
    }

    /// `Process.getOutputStream()`: the child's stdin, writable by the parent.
    func outputStreamRaw() -> Int {
        streamLock.lock()
        defer { streamLock.unlock() }
        if outputStreamRawValue != 0 { return outputStreamRawValue }
        let box = RuntimeOutputStreamBox(sink: RuntimeProcessPipeOutputSink(fileHandle: stdinPipe.fileHandleForWriting))
        outputStreamBox = box
        outputStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.OutputStream", input: false)
        return outputStreamRawValue
    }

    /// `Process.getErrorStream()`: the child's stderr, readable by the parent.
    func errorStreamRaw() -> Int {
        streamLock.lock()
        defer { streamLock.unlock() }
        if errorStreamRawValue != 0 { return errorStreamRawValue }
        let box = RuntimeProcessPipeInputStreamBox(fileHandle: stderrPipe.fileHandleForReading)
        errorStreamBox = box
        errorStreamRawValue = runtimeRegisterIoStream(box, fqName: "java.io.InputStream", input: true)
        return errorStreamRawValue
    }
}

private final class RuntimeProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextHandle = 1
    private var processes: [Int: RuntimeProcessBox] = [:]

    func insert(_ process: Foundation.Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let handle = nextHandle
        nextHandle += 1
        processes[handle] = RuntimeProcessBox(process, stdinPipe: stdinPipe, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        return handle
    }

    func process(for handle: Int) -> RuntimeProcessBox? {
        lock.lock()
        defer { lock.unlock() }
        return processes[handle]
    }
}

private let runtimeProcessRegistry = RuntimeProcessRegistry()

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
/// with stdin/stdout/stderr attached to fresh pipes so the parent can stream
/// the child's output through `Process.getInputStream()`/`getOutputStream()`/
/// `getErrorStream()`.
private func runtimeProcessSpawn(commandRaw: Int, envp: [String]?, dirPath: String?) -> Int {
    guard let command = runtimeStringFromRaw(commandRaw) else { return 0 }
    let arguments = command.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
    guard let executable = arguments.first,
          !executable.isEmpty,
          let executablePath = runtimeProcessExecutablePath(executable)
    else { return 0 }

    let process = Foundation.Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = Array(arguments.dropFirst())

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    // The child receives the ends it reads/writes; the parent keeps the
    // opposite ends for `Process` stream access.
    process.standardInput = stdinPipe.fileHandleForReading
    process.standardOutput = stdoutPipe.fileHandleForWriting
    process.standardError = stderrPipe.fileHandleForWriting
    if let environment = runtimeProcessEnvironment(envp) {
        process.environment = environment
    }
    if let dirPath, !dirPath.isEmpty {
        process.currentDirectoryURL = URL(fileURLWithPath: dirPath)
    }

    do {
        try process.run()
    } catch {
        // The child never started; release every pipe end so no descriptor leaks.
        for handle in [
            stdinPipe.fileHandleForReading, stdinPipe.fileHandleForWriting,
            stdoutPipe.fileHandleForReading, stdoutPipe.fileHandleForWriting,
            stderrPipe.fileHandleForReading, stderrPipe.fileHandleForWriting,
        ] {
            try? handle.close()
        }
        return 0
    }

    // The child owns its dup'd descriptors now. Closing the parent's copies
    // of the child-side ends keeps the descriptor table clean and — for the
    // stdout/stderr write ends — is what lets parent reads observe EOF once
    // the child exits.
    try? stdinPipe.fileHandleForReading.close()
    try? stdoutPipe.fileHandleForWriting.close()
    try? stderrPipe.fileHandleForWriting.close()

    return runtimeProcessRegistry.insert(
        process,
        stdinPipe: stdinPipe,
        stdoutPipe: stdoutPipe,
        stderrPipe: stderrPipe
    )
}

@_cdecl("__kk_process_current_pid")
public func __kk_process_current_pid() -> Int {
    Int(getpid())
}

@_cdecl("__kk_process_start")
public func __kk_process_start(_ commandRaw: Int) -> Int {
    runtimeProcessSpawn(commandRaw: commandRaw, envp: nil, dirPath: nil)
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
        dirPath: runtimeStringFromRaw(dirRaw)
    )
}

@_cdecl("__kk_process_wait_for")
public func __kk_process_wait_for(_ handle: Int) -> Int {
    runtimeProcessRegistry.process(for: handle)?.waitFor() ?? -1
}

@_cdecl("__kk_process_exit_value")
public func __kk_process_exit_value(_ handle: Int) -> Int {
    runtimeProcessRegistry.process(for: handle)?.exitValue() ?? Int.min
}

@_cdecl("__kk_process_is_alive")
public func __kk_process_is_alive(_ handle: Int) -> Int {
    guard let process = runtimeProcessRegistry.process(for: handle) else { return 0 }
    return process.process.isRunning ? 1 : 0
}

@_cdecl("__kk_process_pid")
public func __kk_process_pid(_ handle: Int) -> Int {
    guard let process = runtimeProcessRegistry.process(for: handle) else { return 0 }
    return Int(process.process.processIdentifier)
}

@_cdecl("__kk_process_destroy")
public func __kk_process_destroy(_ handle: Int) {
    runtimeProcessRegistry.process(for: handle)?.destroy()
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
