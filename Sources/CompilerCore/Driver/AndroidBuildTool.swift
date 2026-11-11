import Foundation

package enum AndroidBuildTool {
    package static func run(
        tool: String,
        executable: String,
        arguments: [String],
        currentDirectoryPath: String? = nil,
        phaseTimer: PhaseTimer?,
        subPhaseName: String
    ) throws {
        do {
            _ = try CommandRunner.run(
                executable: executable, arguments: arguments,
                currentDirectoryPath: currentDirectoryPath,
                phaseTimer: phaseTimer, subPhaseName: subPhaseName,
                timeout: 600
            )
        } catch let error as CommandRunnerError {
            throw AndroidPackagingError.commandFailed(tool: tool, detail: describe(error))
        } catch {
            throw AndroidPackagingError.commandFailed(tool: tool, detail: String(describing: error))
        }
    }

    private static func describe(_ error: CommandRunnerError) -> String {
        switch error {
        case let .launchFailed(reason):
            return "failed to launch: \(reason)"
        case let .nonZeroExit(result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            var output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            if output.count > 4_000 { output = String(output.prefix(4_000)) + "…" }
            return "exit \(result.exitCode)\(output.isEmpty ? "" : ": \(output)")"
        case let .timedOut(reason):
            return "timed out: \(reason)"
        }
    }

    package static func makeWorkDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-android-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
