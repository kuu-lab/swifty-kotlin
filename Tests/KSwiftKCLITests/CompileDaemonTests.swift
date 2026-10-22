import Foundation
import CompilerCore
@testable import KSwiftKCLI
import Testing

@Suite("CLI.CompileDaemon", .serialized)
struct CompileDaemonTests {
    @Test
    func watchEnablesIncrementalCompilationForNativeInputs() {
        let native = CLIWatchMode.enablingIncrementalCompilationIfSupported(
            ["input.kt"], emit: .executable
        )
        #expect(native == ["input.kt", "--incremental"])

        let explicitlyDisabled = CLIWatchMode.enablingIncrementalCompilationIfSupported(
            ["--no-incremental", "input.kt"], emit: .executable
        )
        #expect(explicitlyDisabled == ["--no-incremental", "input.kt"])

        let jvm = CLIWatchMode.enablingIncrementalCompilationIfSupported(
            ["--emit", "jar", "input.kt"], emit: .jvmJar
        )
        #expect(jvm == ["--emit", "jar", "input.kt"])
    }

    @Test
    func daemonSerializesConcurrentRequestsAndKeepsTheirResponsesSeparate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (socketPath, socketDirectory) = try makeTemporarySocketPath()
        defer { try? FileManager.default.removeItem(at: socketDirectory) }
        let tracker = ConcurrentRequestTracker()
        let server = CompileDaemonServer(socketPath: socketPath) { request in
            let ordinal = tracker.enter()
            Thread.sleep(forTimeInterval: 0.05)
            tracker.leave()
            return CompileDaemonResponse(
                exitCode: 0,
                stdout: request.arguments.joined(separator: " "),
                stderr: "request-\(ordinal)\n"
            )
        }
        try server.start()
        let serverStopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            server.serveUntilStopped()
            serverStopped.signal()
        }
        defer {
            server.stop()
            _ = serverStopped.wait(timeout: .now() + 5)
        }

        let results = DaemonResponseBox()
        let firstDone = DispatchSemaphore(value: 0)
        let secondDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            results.store(
                CompileDaemonClient.request(arguments: ["alpha"], socketPath: socketPath),
                for: 0
            )
            firstDone.signal()
        }
        DispatchQueue.global().async {
            results.store(
                CompileDaemonClient.request(arguments: ["beta"], socketPath: socketPath),
                for: 1
            )
            secondDone.signal()
        }

        #expect(firstDone.wait(timeout: .now() + 10) == .success)
        #expect(secondDone.wait(timeout: .now() + 10) == .success)
        #expect(results.response(for: 0)?.stdout == "alpha")
        #expect(results.response(for: 1)?.stdout == "beta")
        #expect(tracker.maximumConcurrent == 1)
    }

    @Test
    func daemonMatchesDirectOutputAndDoesNotLeakUserSymbolsAcrossRequests() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (socketPath, socketDirectory) = try makeTemporarySocketPath()
        defer { try? FileManager.default.removeItem(at: socketDirectory) }
        let server = CompileDaemonServer(socketPath: socketPath)
        try server.start()
        let serverStopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            server.serveUntilStopped()
            serverStopped.signal()
        }
        defer {
            server.stop()
            _ = serverStopped.wait(timeout: .now() + 5)
        }

        let source = root.appendingPathComponent("output.kt")
        try "fun main() {}\n".write(to: source, atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("program").path
        let arguments = ["--emit", "kir", "--no-stdlib", "-o", output, source.path]
        let direct = CLIOutputCapture.run {
            CLICompilerService.shared.run(args: arguments)
        }
        let directArtifact = try Data(contentsOf: URL(fileURLWithPath: output + ".kir"))

        let daemon = try #require(CompileDaemonClient.request(arguments: arguments, socketPath: socketPath))
        let daemonArtifact = try Data(contentsOf: URL(fileURLWithPath: output + ".kir"))
        #expect(daemon.exitCode == direct.exitCode)
        #expect(daemon.stdout == direct.stdout)
        #expect(daemon.stderr == direct.stderr)
        #expect(daemonArtifact == directArtifact)

        let declaration = root.appendingPathComponent("declaration.kt")
        try "fun retainedByPreviousRequest(): Int = 7\n".write(to: declaration, atomically: true, encoding: .utf8)
        let declarationResult = try #require(CompileDaemonClient.request(
            arguments: ["--emit", "kir", "--no-stdlib", "-o", root.appendingPathComponent("declaration").path, declaration.path],
            socketPath: socketPath
        ))
        #expect(declarationResult.exitCode == 0)

        let consumer = root.appendingPathComponent("consumer.kt")
        try "fun main() { retainedByPreviousRequest() }\n".write(to: consumer, atomically: true, encoding: .utf8)
        let consumerArguments = ["--emit", "kir", "--no-stdlib", "-o", root.appendingPathComponent("consumer").path, consumer.path]
        let daemonConsumer = try #require(CompileDaemonClient.request(
            arguments: consumerArguments,
            socketPath: socketPath
        ))
        let isolatedConsumer = CLIOutputCapture.run {
            CLICompilerService.shared.run(args: consumerArguments)
        }
        #expect(daemonConsumer.exitCode != 0)
        #expect(daemonConsumer.exitCode == isolatedConsumer.exitCode)
        #expect(daemonConsumer.stderr == isolatedConsumer.stderr)
    }

    @Test
    func missingDaemonFallsBackToDirectCompilation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fallback.kt")
        try "fun main() {}\n".write(to: source, atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("fallback").path
        let exitCode = CLIApplication.runCompilation(
            args: ["--emit", "kir", "--no-stdlib", "-o", output, source.path],
            socketPath: root.appendingPathComponent("missing.sock").path
        )
        #expect(exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: output + ".kir"))
    }

    @Test
    func interruptedDaemonResponseFallsBackToDirectCompilation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (socketPath, socketDirectory) = try makeTemporarySocketPath()
        defer { try? FileManager.default.removeItem(at: socketDirectory) }
        let server = CompileDaemonServer(socketPath: socketPath) { _ in nil }
        try server.start()
        let serverStopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            server.serveUntilStopped()
            serverStopped.signal()
        }
        defer {
            server.stop()
            _ = serverStopped.wait(timeout: .now() + 5)
        }

        let source = root.appendingPathComponent("interrupted.kt")
        try "fun main() {}\n".write(to: source, atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("interrupted").path
        let exitCode = CLIApplication.runCompilation(
            args: ["--emit", "kir", "--no-stdlib", "-o", output, source.path],
            socketPath: socketPath
        )
        #expect(exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: output + ".kir"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-cli-daemon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTemporarySocketPath() throws -> (String, URL) {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ksw-\(UUID().uuidString.prefix(10))", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return (directory.appendingPathComponent("daemon.sock").path, directory)
    }
}

private final class ConcurrentRequestTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maximum = 0
    private var nextOrdinal = 0

    var maximumConcurrent: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximum
    }

    func enter() -> Int {
        lock.lock()
        defer { lock.unlock() }
        active += 1
        maximum = max(maximum, active)
        nextOrdinal += 1
        return nextOrdinal
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        active -= 1
    }
}

private final class DaemonResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int: CompileDaemonResponse?] = [:]

    func store(_ response: CompileDaemonResponse?, for index: Int) {
        lock.lock()
        defer { lock.unlock() }
        values[index] = response
    }

    func response(for index: Int) -> CompileDaemonResponse? {
        lock.lock()
        defer { lock.unlock() }
        return values[index] ?? nil
    }
}
