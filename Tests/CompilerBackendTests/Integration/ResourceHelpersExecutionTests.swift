@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

struct ResourceHelpersExecutionTests {
    @Test func resourceHelpersExecuteAgainstIsolatedResourceRoot() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resourceRoot = temporaryRoot.appendingPathComponent("resources", isDirectory: true)
        let workingDirectory = temporaryRoot.appendingPathComponent("working", isDirectory: true)
        let resourceURL = resourceRoot.appendingPathComponent("Scripts/diff_cases/hello.txt")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try FileManager.default.createDirectory(
            at: resourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try Data("hello resource".utf8).write(to: resourceURL)

        let source = try diffCaseSource("resource_helpers.kt")
        _ = try testStdlibArtifactPath()

        try withTemporaryFile(contents: source) { sourcePath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let options = makeTestOptions(
                moduleName: "ResourceHelpersExecution",
                inputs: [sourcePath],
                outputPath: outputBase,
                emit: .executable,
                allowDefaultStdlibLibrary: true
            )
            let compileResult = makeTestDriver().runForTesting(options: options)
            try assertCompilationSucceeded(compileResult, context: "Resource helper executable compilation")

            let runResult = try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["KSWIFTK_RESOURCE_ROOT=\(resourceRoot.path)", outputBase],
                currentDirectoryPath: workingDirectory.path
            )
            guard runResult.exitCode == 0 else {
                throw TestCompilationFailure(
                    description: "Resource helper executable failed with exit \(runResult.exitCode): \(runResult.stderr)"
                )
            }

            let normalizedOutput = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedOutput == "true\ntrue\ntrue\nhello resource\n104\n")
        }
    }
}
