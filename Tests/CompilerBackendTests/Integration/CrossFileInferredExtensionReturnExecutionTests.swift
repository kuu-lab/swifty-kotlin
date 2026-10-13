#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct CrossFileInferredExtensionReturnExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func arrayPredicateRunsInEitherFileOrder(fromSource: Bool, optimization: Int) throws {
        let sources = [
            """
            package sample
            fun main(){val grid=arrayOf("...".toCharArray());println(listOf(Point(0,0)).filter {grid.isSafe(it)})}
            """,
            """
            package sample
            data class Point(val x:Int,val y:Int)
            fun Array<CharArray>.isSafe(at:Point) = at.y in this.indices && at.x in this[at.y].indices
            """,
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        try withTemporaryFiles(contents: sources) { paths in
            for inputs in [paths, Array(paths.reversed())] {
                let output = directory.appendingPathComponent("array-predicate").path
                let options = CompilerOptions(
                    moduleName: "CrossFileInferredExtensionReturn",
                    inputs: inputs,
                    outputPath: output,
                    emit: .executable,
                    target: defaultTargetTriple(),
                    optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                    stdlibLibraryPath: stdlib,
                    allowDefaultStdlibLibrary: !fromSource
                )
                try assertCompilationSucceeded(
                    makeTestDriver().runForTesting(options: options),
                    context: "cross-file inferred Array extension return"
                )
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(result.stdout == "[Point(x=0, y=0)]\n")
                #expect(result.stderr.isEmpty)
            }
        }
    }
}
#endif
