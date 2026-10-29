@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct RecursiveLocalFunctionCaptureTests {
    @Test(arguments: [true, false], [0, 2])
    func recursiveSearchPreservesCaptures(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(
            diffCaseSource("recursive_local_function_captures.kt", file: #filePath),
            expectedOutput: "2\n", fromSource: fromSource, optimization: optimization
        )
    }

    @Test(arguments: [true, false], [0, 2])
    func recursiveCaptureControls(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(
            diffCaseSource("recursive_local_function_capture_controls.kt", file: #filePath),
            expectedOutput: "120\n6\n16\n13\n7\n7\n", fromSource: fromSource, optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func threeLevelLocalFunctionRecursionPreservesCaptureAndCalls(optimization: Int) throws {
        try compileAndRun(
            diffCaseSource("three_level_recursive_local_functions.kt", file: #filePath),
            expectedOutput: "3\n", fromSource: false, optimization: optimization
        )
    }

    private func compileAndRun(
        _ source: String, expectedOutput: String, fromSource: Bool, optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let library = fromSource ? nil : try testStdlibArtifactPath()
        let options = CompilerOptions(
            moduleName: "KUU1991RecursiveCapture", inputs: [input], outputPath: output,
            emit: .executable, target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource, stdlibLibraryPath: library,
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expectedOutput)
        #expect(execution.stderr.isEmpty)
    }
}
