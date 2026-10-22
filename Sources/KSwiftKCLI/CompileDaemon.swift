import Foundation
import CompilerCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct CompileDaemonRequest: Codable {
    let arguments: [String]
    let workingDirectory: String
}

struct CompileDaemonResponse: Codable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private enum CompileDaemonSocket {
    static var defaultPath: String {
        if let configured = ProcessInfo.processInfo.environment["KSWIFTK_DAEMON_SOCKET"], !configured.isEmpty {
            return configured
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/kswiftk/kswiftc-daemon.sock")
            .path
    }

    static func create() -> Int32 {
        let descriptor: Int32
        #if os(Linux)
        descriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
        if descriptor >= 0 {
            DarwinOrGlibc.preventBrokenPipeSignal(descriptor)
        }
        return descriptor
    }

    static func bind(_ descriptor: Int32, path: String) throws {
        let result = try withAddress(path: path) { address, length in
            DarwinOrGlibc.bind(descriptor, address, length)
        }
        guard result == 0 else { throw socketError("bind", path: path) }
    }

    static func connect(_ descriptor: Int32, path: String) throws {
        let result = try withAddress(path: path) { address, length in
            DarwinOrGlibc.connect(descriptor, address, length)
        }
        guard result == 0 else { throw socketError("connect", path: path) }
    }

    static func isListening(_ descriptor: Int32, path: String) throws -> Bool {
        let result = try withAddress(path: path) { address, length in
            DarwinOrGlibc.connect(descriptor, address, length)
        }
        if result == 0 { return true }
        let errorCode = errno
        guard errorCode == ECONNREFUSED || errorCode == ENOENT else {
            throw socketError("connect", path: path, errorCode: errorCode)
        }
        return false
    }

    static func writeAll(_ descriptor: Int32, data: Data) throws {
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return DarwinOrGlibc.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
            }
            guard count > 0 else { throw socketError("write", path: "daemon connection") }
            offset += count
        }
    }

    private static func withAddress<Result>(
        path: String,
        _ operation: (UnsafePointer<sockaddr>, socklen_t) -> Result
    ) throws -> Result {
        let bytes = Array(path.utf8CString)
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else {
            throw CompileDaemonError.message("Daemon socket path is too long: \(path)")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            pathPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                bytes.withUnsafeBufferPointer { source in
                    destination.update(from: source.baseAddress!, count: bytes.count)
                }
            }
        }
        let addressLength = MemoryLayout<sockaddr_un>.size - capacity + bytes.count
        #if canImport(Darwin)
        address.sun_len = UInt8(addressLength)
        #endif
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                operation($0, socklen_t(addressLength))
            }
        }
    }

    private static func socketError(
        _ operation: String,
        path: String,
        errorCode: Int32 = errno
    ) -> CompileDaemonError {
        CompileDaemonError.message("Daemon socket \(operation) failed at '\(path)': \(String(cString: strerror(errorCode)))")
    }
}

private enum DarwinOrGlibc {
    static func bind(_ descriptor: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
        #if canImport(Darwin)
        Darwin.bind(descriptor, address, length)
        #else
        Glibc.bind(descriptor, address, length)
        #endif
    }

    static func connect(_ descriptor: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
        #if canImport(Darwin)
        Darwin.connect(descriptor, address, length)
        #else
        Glibc.connect(descriptor, address, length)
        #endif
    }

    static func send(_ descriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if os(Linux)
        Glibc.send(descriptor, buffer, count, Int32(MSG_NOSIGNAL))
        #else
        Darwin.send(descriptor, buffer, count, 0)
        #endif
    }

    static func preventBrokenPipeSignal(_ descriptor: Int32) {
        #if canImport(Darwin)
        var enabled: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        )
        #endif
    }
}

private enum CompileDaemonError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(value): value
        }
    }
}

final class CompileDaemonServer: @unchecked Sendable {
    private let socketPath: String
    private let handler: (CompileDaemonRequest) -> CompileDaemonResponse?
    private let lock = NSLock()
    private var listener = Int32(-1)
    private var ownsSocketPath = false

    init(
        socketPath: String? = nil,
        handler: ((CompileDaemonRequest) -> CompileDaemonResponse?)? = nil
    ) {
        self.socketPath = socketPath ?? CompileDaemonSocket.defaultPath
        if handler == nil {
            KklibSemaSession.isEnabled = true
        }
        self.handler = handler ?? { CompileDaemonServer.compile($0) }
    }

    func runForeground() -> Int32 {
        do {
            try start()
        } catch {
            FileHandle.standardError.write(Data("kswiftc daemon: \(error)\n".utf8))
            return 1
        }
        print("kswiftc daemon listening at \(socketPath)")
        serveUntilStopped()
        stop()
        return 0
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listener < 0 else { return }

        try prepareSocketDirectory()
        try removeStaleSocket()

        let descriptor = CompileDaemonSocket.create()
        guard descriptor >= 0 else {
            throw CompileDaemonError.message("Could not create daemon socket: \(String(cString: strerror(errno)))")
        }
        do {
            try CompileDaemonSocket.bind(descriptor, path: socketPath)
            ownsSocketPath = true
            guard chmod(socketPath, 0o600) == 0 else {
                throw CompileDaemonError.message("Could not secure daemon socket '\(socketPath)'.")
            }
            guard listen(descriptor, 16) == 0 else {
                throw CompileDaemonError.message("Could not listen on daemon socket '\(socketPath)'.")
            }
            listener = descriptor
        } catch {
            close(descriptor)
            if ownsSocketPath { unlink(socketPath) }
            ownsSocketPath = false
            throw error
        }
    }

    func serveUntilStopped() {
        lock.lock()
        let descriptor = listener
        lock.unlock()
        guard descriptor >= 0 else { return }

        while true {
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                lock.lock()
                let isStopped = listener < 0
                lock.unlock()
                if isStopped || errno == EINTR { if isStopped { return }; continue }
                return
            }
            DarwinOrGlibc.preventBrokenPipeSignal(client)
            serve(client)
        }
    }

    func stop() {
        lock.lock()
        let descriptor = listener
        listener = -1
        let shouldUnlink = ownsSocketPath
        ownsSocketPath = false
        lock.unlock()

        if descriptor >= 0 {
            _ = shutdown(descriptor, Int32(SHUT_RDWR))
            close(descriptor)
        }
        if shouldUnlink { _ = unlink(socketPath) }
    }

    private func prepareSocketDirectory() throws {
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var info = stat()
        guard lstat(directory, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == geteuid()
        else {
            throw CompileDaemonError.message("Daemon socket directory is not a private directory owned by the current user: \(directory)")
        }
        guard chmod(directory, 0o700) == 0 else {
            throw CompileDaemonError.message("Could not secure daemon socket directory '\(directory)'.")
        }
    }

    private func removeStaleSocket() throws {
        var info = stat()
        guard lstat(socketPath, &info) == 0 else {
            if errno == ENOENT { return }
            throw CompileDaemonError.message("Could not inspect daemon socket '\(socketPath)'.")
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK), info.st_uid == geteuid() else {
            throw CompileDaemonError.message("Refusing to replace a non-owned daemon socket path: \(socketPath)")
        }

        let probe = CompileDaemonSocket.create()
        guard probe >= 0 else { throw CompileDaemonError.message("Could not probe existing daemon socket.") }
        let isListening: Bool
        do {
            isListening = try CompileDaemonSocket.isListening(probe, path: socketPath)
        } catch {
            close(probe)
            throw error
        }
        close(probe)
        if isListening {
            throw CompileDaemonError.message("A kswiftc daemon is already listening at \(socketPath)")
        }
        guard unlink(socketPath) == 0 || errno == ENOENT else {
            throw CompileDaemonError.message("Could not remove stale daemon socket '\(socketPath)'.")
        }
    }

    private func serve(_ descriptor: Int32) {
        let connection = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { connection.closeFile() }
        do {
            guard let requestData = try readRequest(from: connection),
                  let request = try? JSONDecoder().decode(CompileDaemonRequest.self, from: requestData)
            else {
                try CompileDaemonSocket.writeAll(descriptor, data: Self.encode(CompileDaemonResponse(
                    exitCode: 2,
                    stdout: "",
                    stderr: "Invalid compile daemon request.\n"
                )))
                return
            }
            guard let response = handler(request) else { return }
            try CompileDaemonSocket.writeAll(descriptor, data: Self.encode(response))
        } catch {
            let response = CompileDaemonResponse(exitCode: 1, stdout: "", stderr: "kswiftc daemon: \(error)\n")
            try? CompileDaemonSocket.writeAll(descriptor, data: Self.encode(response))
        }
    }

    private func readRequest(from connection: FileHandle) throws -> Data? {
        let maximumRequestSize = 4 * 1024 * 1024
        var data = Data()
        while data.count <= maximumRequestSize {
            let remainingCapacity = maximumRequestSize + 1 - data.count
            guard let chunk = try connection.read(upToCount: min(4096, remainingCapacity)), !chunk.isEmpty else { break }
            data.append(chunk)
            if let newline = data.firstIndex(of: 10) {
                guard newline <= maximumRequestSize else { return nil }
                return Data(data[..<newline])
            }
        }
        return nil
    }

    private static func encode(_ response: CompileDaemonResponse) -> Data {
        var data = (try? JSONEncoder().encode(response)) ?? Data("{}".utf8)
        data.append(10)
        return data
    }

    private static func compile(_ request: CompileDaemonRequest) -> CompileDaemonResponse {
        let previousDirectory = FileManager.default.currentDirectoryPath
        guard FileManager.default.changeCurrentDirectoryPath(request.workingDirectory) else {
            return CompileDaemonResponse(
                exitCode: 1,
                stdout: "",
                stderr: "Cannot enter working directory: \(request.workingDirectory)\n"
            )
        }
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previousDirectory) }
        return CLIOutputCapture.run {
            CLICompilerService.shared.run(args: request.arguments)
        }
    }
}

enum CompileDaemonClient {
    static func request(
        arguments: [String],
        socketPath: String? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> CompileDaemonResponse? {
        let resolvedSocketPath = socketPath ?? CompileDaemonSocket.defaultPath
        let descriptor = CompileDaemonSocket.create()
        guard descriptor >= 0 else { return nil }
        do {
            try CompileDaemonSocket.connect(descriptor, path: resolvedSocketPath)
        } catch {
            close(descriptor)
            return nil
        }

        let connection = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { connection.closeFile() }
        let request = CompileDaemonRequest(arguments: arguments, workingDirectory: workingDirectory)
        do {
            var requestData = try JSONEncoder().encode(request)
            requestData.append(10)
            try CompileDaemonSocket.writeAll(descriptor, data: requestData)
            _ = shutdown(descriptor, Int32(SHUT_WR))
            guard let responseData = try connection.readToEnd(),
                  let newline = responseData.firstIndex(of: 10)
            else { return nil }
            return try JSONDecoder().decode(CompileDaemonResponse.self, from: Data(responseData[..<newline]))
        } catch {
            return nil
        }
    }
}

enum CLIOutputCapture {
    static func run(_ body: () -> Int32) -> CompileDaemonResponse {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftc-daemon-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return CompileDaemonResponse(exitCode: 1, stdout: "", stderr: "Cannot create output capture directory: \(error)\n")
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdoutPath = directory.appendingPathComponent("stdout").path
        let stderrPath = directory.appendingPathComponent("stderr").path
        let stdoutFD = open(stdoutPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        let stderrFD = open(stderrPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard stdoutFD >= 0, stderrFD >= 0 else {
            if stdoutFD >= 0 { close(stdoutFD) }
            if stderrFD >= 0 { close(stderrFD) }
            return CompileDaemonResponse(exitCode: 1, stdout: "", stderr: "Cannot open output capture files.\n")
        }
        let savedStdout = dup(STDOUT_FILENO)
        let savedStderr = dup(STDERR_FILENO)
        guard savedStdout >= 0, savedStderr >= 0 else {
            close(stdoutFD)
            close(stderrFD)
            if savedStdout >= 0 { close(savedStdout) }
            if savedStderr >= 0 { close(savedStderr) }
            return CompileDaemonResponse(exitCode: 1, stdout: "", stderr: "Cannot redirect compiler output.\n")
        }

        fflush(nil)
        _ = dup2(stdoutFD, STDOUT_FILENO)
        _ = dup2(stderrFD, STDERR_FILENO)
        let exitCode = body()
        fflush(nil)
        _ = dup2(savedStdout, STDOUT_FILENO)
        _ = dup2(savedStderr, STDERR_FILENO)
        close(stdoutFD)
        close(stderrFD)
        close(savedStdout)
        close(savedStderr)

        let stdout = (try? String(contentsOfFile: stdoutPath, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOfFile: stderrPath, encoding: .utf8)) ?? ""
        return CompileDaemonResponse(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }
}
