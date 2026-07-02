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

private final class CommandPipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let output: LockedCommandOutput
    private let stream: CommandOutputStream
    private let group: DispatchGroup
    private let name: String

    init(handle: FileHandle, output: LockedCommandOutput, stream: CommandOutputStream, group: DispatchGroup, name: String) {
        self.handle = handle
        self.output = output
        self.stream = stream
        self.group = group
        self.name = name
    }

    func start() {
        group.enter()
        let thread = Thread { [self] in
            defer { group.leave() }
            output.store(handle.readDataToEndOfFile(), for: stream)
        }
        thread.name = name
        thread.start()
    }
}

package enum CommandRunner {
    private static let drainTimeoutSeconds: TimeInterval = 20
    private static let terminationGracePeriodSeconds: TimeInterval = 1

    package static func resolveExecutable(_ name: String, fallback: String) -> String {
        let fileManager = FileManager.default
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathEnv.split(separator: ":") {
                let candidate = String(directory) + "/" + name
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return fallback
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
        let stdoutReadHandle = stdoutPipe.fileHandleForReading
        let stderrReadHandle = stderrPipe.fileHandleForReading
        let stdoutWriteHandle = stdoutPipe.fileHandleForWriting
        let stderrWriteHandle = stderrPipe.fileHandleForWriting
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Drain both pipes before waiting for process termination to avoid
        // deadlocks when child output exceeds the kernel pipe buffer.
        let output = LockedCommandOutput()
        let drainGroup = DispatchGroup()
        let stdoutDrain = CommandPipeDrain(
            handle: stdoutReadHandle,
            output: output,
            stream: .stdout,
            group: drainGroup,
            name: "CommandRunner.stdout"
        )
        let stderrDrain = CommandPipeDrain(
            handle: stderrReadHandle,
            output: output,
            stream: .stderr,
            group: drainGroup,
            name: "CommandRunner.stderr"
        )
        stdoutDrain.start()
        stderrDrain.start()

        let terminatedSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminatedSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            stdoutWriteHandle.closeFile()
            stderrWriteHandle.closeFile()
            _ = wait(for: drainGroup, timeout: drainTimeoutSeconds)
            throw CommandRunnerError.launchFailed("Failed to launch \(executable): \(error)")
        }
        stdoutWriteHandle.closeFile()
        stderrWriteHandle.closeFile()

        var didExit = wait(for: terminatedSemaphore, timeout: timeout)
        let didTimeOut = !didExit
        if !didExit {
            process.terminate()
            didExit = wait(for: terminatedSemaphore, timeout: terminationGracePeriodSeconds)
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
                didExit = wait(for: terminatedSemaphore, timeout: terminationGracePeriodSeconds)
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

    private static func wait(for semaphore: DispatchSemaphore, timeout: TimeInterval) -> Bool {
        let milliseconds = max(1, Int((timeout * 1000).rounded()))
        return semaphore.wait(timeout: .now() + .milliseconds(milliseconds)) == .success
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
