import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

package struct CommandResult: Sendable {
    package let exitCode: Int32
    package let stdout: String
    package let stderr: String
}

package enum CommandRunnerError: Error, Sendable {
    case launchFailed(String)
    case nonZeroExit(CommandResult)
    case timedOut(String)
}

private enum CommandOutputStream {
    case stdout
    case stderr
}

private final class LockedCommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func store(_ data: Data, for stream: CommandOutputStream) {
        lock.lock()
        switch stream {
        case .stdout:
            stdoutData = data
        case .stderr:
            stderrData = data
        }
        lock.unlock()
    }

    func data(for stream: CommandOutputStream) -> Data {
        lock.lock()
        defer { lock.unlock() }
        switch stream {
        case .stdout:
            return stdoutData
        case .stderr:
            return stderrData
        }
    }
}

package enum CommandRunner {
    private static let drainTimeoutSeconds: TimeInterval = 20
    private static let terminationGracePeriodSeconds: TimeInterval = 1

    /// Resolves an executable by scanning `$PATH`, but only trusts directories
    /// that cannot be tampered with by another local user. This prevents a
    /// PATH-hijack where a malicious `name` planted in an attacker-controlled
    /// directory earlier in `$PATH` would be executed with the victim's
    /// privileges. Empty, relative, group/other-writable, or foreign-owned PATH
    /// entries are skipped; if no trusted match is found, `fallback` is returned.
    package static func resolveExecutable(_ name: String, fallback: String) -> String {
        let fileManager = FileManager.default
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathEnv.split(separator: ":", omittingEmptySubsequences: false) {
                let directoryPath = String(directory)
                // An empty entry resolves to the current working directory and a
                // relative entry can be influenced by the process's CWD; neither
                // is trustworthy, so require an absolute path.
                guard directoryPath.hasPrefix("/") else { continue }
                guard isTrustedDirectory(directoryPath, fileManager: fileManager) else { continue }
                let candidate = directoryPath + "/" + name
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return fallback
    }

    /// A directory is trusted for executable resolution only when it exists, is
    /// a directory, is not writable by group or others, and is owned by `root`
    /// or the current user. This rejects directories another local user could
    /// use to plant a malicious binary.
    private static func isTrustedDirectory(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        // Resolve symlinks so we inspect the target directory's attributes
        // rather than the link's (symlinks always report 0o777 permissions,
        // e.g. /bin -> /usr/bin on modern Debian/Ubuntu).
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolvedPath) else {
            return false
        }
        guard let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value else {
            return false
        }
        let groupWrite: UInt16 = 0o020
        let otherWrite: UInt16 = 0o002
        if permissions & (groupWrite | otherWrite) != 0 {
            return false
        }
        // Fail closed: if ownership can't be determined, treat the directory as
        // untrusted rather than assuming it is safe.
        guard let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value else {
            return false
        }
        if owner != 0 && owner != getuid() {
            return false
        }
        return true
    }

    /// Runs a command and records its wall-clock time as a sub-phase in the
    /// given `PhaseTimer`, if non-nil.  The `subPhaseName` label appears in
    /// the `time-phases` output.
    package static func run(
        executable: String,
        arguments: [String],
        currentDirectoryPath: String? = nil,
        phaseTimer: PhaseTimer? = nil,
        subPhaseName: String? = nil,
        timeout: TimeInterval = 120
    ) throws -> CommandResult {
        let startTime: UInt64 = (phaseTimer != nil && subPhaseName != nil) ? DispatchTime.now().uptimeNanoseconds : 0
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed("Failed to launch \(executable): \(error)")
        }
        // Drain both pipes before waiting for process termination to avoid
        // deadlocks when child output exceeds the kernel pipe buffer.
        let output = LockedCommandOutput()
        let drainGroup = DispatchGroup()
        let exitGroup = DispatchGroup()

        drainGroup.enter()
        DispatchQueue.global().async {
            defer { drainGroup.leave() }
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            output.store(data, for: .stdout)
        }
        drainGroup.enter()
        DispatchQueue.global().async {
            defer { drainGroup.leave() }
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            output.store(data, for: .stderr)
        }

        exitGroup.enter()
        DispatchQueue.global().async {
            defer { exitGroup.leave() }
            process.waitUntilExit()
        }

        var didExit = wait(for: exitGroup, timeout: timeout)
        let didTimeOut = !didExit
        if !didExit {
            process.terminate()
            // Re-enter group to wait for process exit after terminate
            exitGroup.enter()
            DispatchQueue.global().async {
                defer { exitGroup.leave() }
                process.waitUntilExit()
            }
            didExit = wait(for: exitGroup, timeout: terminationGracePeriodSeconds)
            if !didExit {
                // Check if process is still running before sending SIGKILL to avoid killing wrong process
                // Note: There's a race condition between this check and the kill() call where the process
                // could exit and the PID could be reused. This is a fundamental limitation of the kill() API.
                if process.isRunning {
                    let killResult = kill(process.processIdentifier, SIGKILL)
                    if killResult != 0 && errno != ESRCH {
                        // kill() failed with error other than ESRCH (no such process)
                        // ESRCH is expected if process exited between isRunning check and kill call
                        // Other errors are unusual but we continue anyway
                    }
                }
                // Re-enter group to wait for process exit after SIGKILL
                exitGroup.enter()
                DispatchQueue.global().async {
                    defer { exitGroup.leave() }
                    process.waitUntilExit()
                }
                didExit = wait(for: exitGroup, timeout: terminationGracePeriodSeconds)
                // Verify process exited after SIGKILL
                if !didExit && process.isRunning {
                    // Process is still running despite SIGKILL - this is unusual but possible
                    // Log warning and continue - process should be dead by now
                    // (We don't have a logging mechanism here, but the drain operations may fail)
                }
            }
        }

        let didDrain = wait(for: drainGroup, timeout: drainTimeoutSeconds)

        let stdout = String(decoding: output.data(for: .stdout), as: UTF8.self)
        let stderr = String(decoding: output.data(for: .stderr), as: UTF8.self)

        // Once the initial wait exceeds the timeout budget, surface a timeout
        // even if terminate()/SIGKILL eventually forces a non-zero exit code.
        if didTimeOut {
            throw CommandRunnerError.timedOut(timeoutMessage(
                executable: executable,
                arguments: arguments,
                timeout: timeout,
                stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                didExit: didExit,
                didDrain: didDrain
            ))
        }

        let result = CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )

        // If process exited but drain failed, check exit status
        if !didDrain {
            if result.exitCode == 0 {
                // Process succeeded but drain failed - report as timeout
                throw CommandRunnerError.timedOut(timeoutMessage(
                    executable: executable,
                    arguments: arguments,
                    timeout: timeout,
                    stdout: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                    didExit: didExit,
                    didDrain: didDrain
                ))
            }
            // Process failed with non-zero exit code - fall through to throw nonZeroExit below
        }
        // Record subprocess wall-clock time when a timer is active.
        if let timer = phaseTimer, let label = subPhaseName {
            let endTime = DispatchTime.now().uptimeNanoseconds
            timer.recordSubPhase(label, startTime: startTime, endTime: endTime)
        }

        if result.exitCode != 0 {
            throw CommandRunnerError.nonZeroExit(result)
        }
        return result
    }

    private static func wait(for group: DispatchGroup, timeout: TimeInterval) -> Bool {
        let milliseconds = max(1, Int((timeout * 1000).rounded()))
        return group.wait(timeout: .now() + .milliseconds(milliseconds)) == .success
    }

    private static func timeoutMessage(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        stdout: String,
        stderr: String,
        didExit: Bool,
        didDrain: Bool
    ) -> String {
        let command = ([executable] + arguments).joined(separator: " ")
        let phase: String
        if !didExit {
            phase = "waiting for process exit"
        } else if !didDrain {
            phase = "draining process output"
        } else {
            phase = "running command"
        }
        let stdoutSuffix = stdout.isEmpty ? "" : "\nSTDOUT: \(stdout)"
        let stderrSuffix = stderr.isEmpty ? "" : "\nSTDERR: \(stderr)"
        return "Timed out after \(timeout)s while \(phase): \(command)\(stdoutSuffix)\(stderrSuffix)"
    }
}
