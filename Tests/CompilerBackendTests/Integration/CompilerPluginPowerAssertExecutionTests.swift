@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CompilerPluginPowerAssertExecutionTests {

    @Test
    func powerAssertFormatsSubExpressionDiagramAtRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let wrappedSource = """
        package com.example

        fun main() {
            val a = 1
            val b = 2
            val c = 5
            try {
                require(a + b == c)
            } catch (e: Throwable) {
                println(e.message)
            }
        }
        """

        let inputPath = directory.appendingPathComponent("power_assert_exec.kt").path
        let outputPath = directory.appendingPathComponent("power_assert_exec_out").path
        try wrappedSource.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "PowerAssertExec",
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            frontendFlags: ["plugin:org.jetbrains.kotlin.powerassert:function=kotlin.require"],
            includeStdlib: false,
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        let output = result.stdout
        #expect(output.contains("require(a + b == c)"), "Expected source call line in diagram: \(output)")
        #expect(output.contains("|"), "Expected pipe diagram in output: \(output)")
        #expect(output.contains("3"), "Expected intermediate sum (1 + 2 = 3) in output: \(output)")
        #expect(output.contains("5"), "Expected RHS value (5) in output: \(output)")
        #expect(output.contains("false"), "Expected comparison result (false) in output: \(output)")
    }
}
