#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite
struct CommandRunnerTests {
    private static let pathEnvironmentLock = NSLock()

    // MARK: - resolveExecutable

    @Test
    func testResolveExecutableFindsExistingCommand() {
        Self.withPathEnvironmentLock {
            let resolved = CommandRunner.resolveExecutable("ls", fallback: "/nonexistent/ls")
            #expect(resolved.hasSuffix("/ls"), "Expected resolved path to end with /ls, got: \(resolved)")
            #expect(resolved != "/nonexistent/ls", "Should have found ls in PATH")
        }
    }

    @Test
    func testResolveExecutableFallsBackForMissingCommand() {
        Self.withPathEnvironmentLock {
            let fallback = "/this/path/does/not/exist/in/PATH"
            let resolved = CommandRunner.resolveExecutable("__command_that_definitely_does_not_exist__", fallback: fallback)
            #expect(resolved == fallback)
        }
    }

    @Test
    func testResolveExecutableReturnsFullPath() {
        Self.withPathEnvironmentLock {
            let resolved = CommandRunner.resolveExecutable("echo", fallback: "/bin/echo")
            #expect(resolved.hasPrefix("/"), "Resolved path should be absolute, got: \(resolved)")
        }
    }

    @Test
    func testResolveExecutableSkipsUntrustedPATHDirectory() throws {
        let toolName = "kswiftk_fake_tool_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let fallback = "/this/path/does/not/exist/\(toolName)"
        let directory = try makeTemporaryToolDirectory(permissions: 0o777, toolName: toolName)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Self.withTemporaryPath([directory.path]) {
            let resolved = CommandRunner.resolveExecutable(toolName, fallback: fallback)
            #expect(resolved == fallback)
        }
    }

    @Test
    func testResolveExecutableReturnsTrustedPATHDirectoryExecutable() throws {
        let toolName = "kswiftk_fake_tool_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let directory = try makeTemporaryToolDirectory(permissions: 0o755, toolName: toolName)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Self.withTemporaryPath([directory.path]) {
            let fallback = "/this/path/does/not/exist/\(toolName)"
            let resolved = CommandRunner.resolveExecutable(toolName, fallback: fallback)
            #expect(resolved == directory.appendingPathComponent(toolName).path)
        }
    }

    // MARK: - run: stdout / exit code

    @Test
    func testRunSuccessfulCommandReturnsZeroExitCode() throws {
        let result = try CommandRunner.run(executable: "/bin/echo", arguments: [])
        #expect(result.exitCode == 0)
    }

    @Test
    func testRunCommandCapturesStdout() throws {
        let result = try CommandRunner.run(executable: "/bin/echo", arguments: ["hello world"])
        #expect(result.stdout.contains("hello world"),
                      "Expected stdout to contain 'hello world', got: \(result.stdout)")
    }

    @Test
    func testRunCommandCapturesMultipleArguments() throws {
        let result = try CommandRunner.run(executable: "/bin/echo", arguments: ["foo", "bar"])
        #expect(result.stdout.contains("foo"), "Expected stdout to contain 'foo'")
        #expect(result.stdout.contains("bar"), "Expected stdout to contain 'bar'")
    }

    // MARK: - run: nonzero exit

    @Test
    func testRunNonZeroExitThrowsNonZeroExitError() {
        do {
            _ = try CommandRunner.run(executable: "/usr/bin/false", arguments: [])
            Issue.record("Expected nonZeroExit error to be thrown")
        } catch let CommandRunnerError.nonZeroExit(result) {
            #expect(result.exitCode != 0)
        } catch {
            Issue.record("Expected nonZeroExit error, got: \(error)")
        }
    }

    @Test
    func testNonZeroExitErrorContainsCommandResult() {
        do {
            _ = try CommandRunner.run(executable: "/usr/bin/false", arguments: [])
            Issue.record("Expected nonZeroExit to be thrown")
        } catch let CommandRunnerError.nonZeroExit(result) {
            #expect(result.exitCode != 0)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - run: launch failure

    @Test
    func testRunNonexistentExecutableThrowsLaunchFailed() {
        do {
            _ = try CommandRunner.run(executable: "/nonexistent/binary/path", arguments: [])
            Issue.record("Expected launchFailed error to be thrown")
        } catch CommandRunnerError.launchFailed {
            // expected
        } catch {
            Issue.record("Expected launchFailed error, got: \(error)")
        }
    }

    // MARK: - run: stderr capture

    @Test
    func testRunCommandCapturesStderr() throws {
        // /bin/sh -c "echo errormsg >&2" writes to stderr
        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo errormsg >&2"]
        )
        #expect(result.stderr.contains("errormsg"),
                      "stderr should contain the error message")
    }

    @Test
    func testRunLargeOutputDoesNotDeadlock() throws {
        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes x | head -c 131072"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 131_072)
    }

    @Test
    func testRunLargeStderrDoesNotDeadlock() throws {
        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes e | head -c 131072 1>&2"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stderr.count == 131_072)
    }

    @Test
    func testRunTimedOutProcessThrowsTimedOutError() throws {
        #if !os(Linux)
        // On Linux, swift-corelibs-foundation's Process termination is unreliable and
        // can raise SIGABRT under heavy parallelism. Test is macOS-only.
        do {
            _ = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 10"],
                timeout: 0.1
            )
            Issue.record("Expected timedOut error to be thrown")
        } catch let CommandRunnerError.timedOut(message) {
            #expect(message.contains("Timed out"))
            #expect(message.contains("sleep 10"))
        } catch {
            Issue.record("Expected timedOut error, got: \(error)")
        }
        #endif
    }

    // MARK: - run: currentDirectoryPath

    @Test
    func testRunCurrentDirectoryPathSetsWorkingDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.path
        let result = try CommandRunner.run(
            executable: "/bin/pwd",
            arguments: [],
            currentDirectoryPath: tmpDir
        )
        let normalized = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // On macOS, /var/folders may be a symlink to /private/var/folders.
        // Accept either the original or resolved path.
        let resolvedTmp = (try? FileManager.default.destinationOfSymbolicLink(atPath: tmpDir)) ?? tmpDir
        #expect(
            normalized == tmpDir || normalized == resolvedTmp || normalized.hasPrefix("/private"),
            "Expected pwd output to match tmpDir, got: \(normalized)"
        )
    }

    private static func withPathEnvironmentLock<T>(_ body: () throws -> T) rethrows -> T {
        pathEnvironmentLock.lock()
        defer { pathEnvironmentLock.unlock() }
        return try body()
    }

    private static func withTemporaryPath<T>(_ directories: [String], body: () throws -> T) throws -> T {
        try withPathEnvironmentLock {
            let previousPath = getenv("PATH").map { String(cString: $0) }
            setenv("PATH", directories.joined(separator: ":"), 1)
            defer {
                if let previousPath {
                    setenv("PATH", previousPath, 1)
                } else {
                    unsetenv("PATH")
                }
            }
            return try body()
        }
    }

    private func makeTemporaryToolDirectory(permissions: Int16, toolName: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: directory.path
        )

        let toolURL = directory.appendingPathComponent(toolName)
        let script = "#!/bin/sh\nexit 0\n"
        guard fileManager.createFile(atPath: toolURL.path, contents: script.data(using: .utf8)) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue)
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: toolURL.path
        )
        return directory
    }
}
#endif
