@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testUninitializedLocalFirstAssignmentCopiesItsSource(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        let source = """
        fun main() {
            var i = 1
            var k: Int
            k = i
            k++
            println(i)
            println(k)

            var initializedSource = 3
            var initialized = initializedSource
            initialized++
            println(initializedSource)
            println(initialized)

            var reassignmentSource = 5
            var reassigned: Int
            reassigned = reassignmentSource
            reassigned = 8
            println(reassignmentSource)
            println(reassigned)

            var snapshotSource = 9
            var snapshot: Int
            snapshot = snapshotSource
            snapshotSource = 11
            println(snapshot)
            println(snapshotSource)

            var capturedSource = 12
            var capturedLocal: Int
            capturedLocal = capturedSource
            val incrementCapture = { capturedLocal++ }
            incrementCapture()
            println(capturedSource)
            println(capturedLocal)

            var loopSource = 13
            var loopLocal: Int
            for (iteration in 1..1) {
                loopLocal = loopSource
                loopLocal++
                println(loopLocal)
            }
            println(loopSource)
        }
        """
        let expected = "1\n2\n3\n4\n5\n8\n9\n11\n12\n13\n14\n13\n"
        let target = defaultTargetTriple()
        let stdlibLibraryPath = useStdlibLibrary ? try testStdlibArtifactPath() : nil

        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: "KUU1855UninitializedLocal",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: target,
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            )
            let compilation = makeTestDriver().runForTesting(options: options)
            try assertCompilationSucceeded(compilation)

            let execution = try CommandRunner.run(executable: outputPath, arguments: [], timeout: 10)
            #expect(execution.exitCode == 0, "Execution failed: \(execution.stderr)")
            #expect(Data(execution.stdout.utf8) == Data(expected.utf8))
        }
    }
}
