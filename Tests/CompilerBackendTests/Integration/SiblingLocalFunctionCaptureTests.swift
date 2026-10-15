@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct SiblingLocalFunctionCaptureTests {
    // Source-stdlib O2 currently fails LLVM verification even for println("OK")
    // (KUU-2387); exercise O2 using a newly built stdlib artifact instead.
    @Test(arguments: [(true, 0), (false, 0), (false, 2)])
    func siblingCallsForwardCalleeCaptures(lane: (Bool, Int)) throws {
        try compileAndRun(
            diffCaseSource("sibling_local_function_captures.kt", file: #filePath),
            expectedOutput: "13.0\n33.0\n33.0\n3.0\n",
            fromSource: lane.0, optimization: lane.1
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
        let target = CompilerTestSupport.defaultTargetTriple()
        let library = fromSource ? nil : try StdlibArtifactBuilder.build(
            outputBase: directory.appendingPathComponent("stdlib").path, target: target
        )
        let options = CompilerOptions(
            moduleName: "KUU2328SiblingCapture", inputs: [input], outputPath: output,
            emit: .executable, target: target,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource, stdlibLibraryPath: library,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expectedOutput)
        #expect(execution.stderr.isEmpty)
    }
}
