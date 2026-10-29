@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct CapturedLocalFunctionArrayAccessTests {
    @Test(arguments: [true, false], [0, 2])
    func localFunctionWithCaptureAndIndexedArrayAccess(fromSource: Bool, optimization: Int) throws {
        let source = """
        fun outer(n: Int) {
            fun inner(k: Int, c: IntArray) {
                c[k] = 7
                println(n)
            }
            val c = IntArray(4)
            inner(1, c)
            println(c[1])
        }
        fun main() {
            outer(4)
        }
        """
        try compileAndRun(
            source,
            expectedOutput: "4\n7\n",
            fromSource: fromSource,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func localFunctionWithCaptureAndMultipleParameters(optimization: Int) throws {
        let source = """
        fun outer(prefix: String, multiplier: Int) {
            fun updateAndPrint(index: Int, arr: IntArray, value: Int, label: String) {
                arr[index] = value * multiplier
                println(prefix + label + ": " + arr[index])
            }
            val arr = IntArray(3)
            updateAndPrint(2, arr, 5, "item")
            println(arr[2])
        }
        fun main() {
            outer("test_", 10)
        }
        """
        try compileAndRun(
            source,
            expectedOutput: "test_item: 50\n50\n",
            fromSource: false,
            optimization: optimization
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
            moduleName: "KUU2664CaptureArrayAccess", inputs: [input], outputPath: output,
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
