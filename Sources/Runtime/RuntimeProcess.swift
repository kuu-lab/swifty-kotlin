import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

private final class RuntimeProcessBox: @unchecked Sendable {
    let process: Foundation.Process

    init(_ process: Foundation.Process) {
        self.process = process
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
}

private final class RuntimeProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextHandle = 1
    private var processes: [Int: RuntimeProcessBox] = [:]

    func insert(_ process: Foundation.Process) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let handle = nextHandle
        nextHandle += 1
        processes[handle] = RuntimeProcessBox(process)
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

@_cdecl("__kk_process_current_pid")
public func __kk_process_current_pid() -> Int {
    Int(getpid())
}

@_cdecl("__kk_process_start")
public func __kk_process_start(_ commandRaw: Int) -> Int {
    guard let command = runtimeStringFromRaw(commandRaw) else { return 0 }
    let arguments = command.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
    guard let executable = arguments.first,
          !executable.isEmpty,
          let executablePath = runtimeProcessExecutablePath(executable)
    else { return 0 }

    let process = Foundation.Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = Array(arguments.dropFirst())
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    do {
        try process.run()
    } catch {
        return 0
    }
    return runtimeProcessRegistry.insert(process)
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
