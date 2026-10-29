@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-1917: Iterable pair zip is infix in both source and serialized stdlib paths,
    /// while the two-parameter transform overload remains a regular call.
    @Test(arguments: [true, false], [0, 2])
    func testIterableZipInfixThroughSourceAndFreshArtifact(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        fun main() {
            println((listOf(1,2) zip listOf(3,4)).joinToString())
            println((listOf(1,2) zip listOf(3,4,5)).joinToString())
            println(listOf(1,2,3).zip(listOf(4,5)).joinToString())
            println(listOf(1,2,3).zip(listOf(4,5)) { left, right -> "$left:$right" }.joinToString())
        }
        """
        let input = directory.appendingPathComponent("IterableZip.kt").path
        let output = directory.appendingPathComponent("IterableZip").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        if let artifactPath {
            let metadataPath = URL(fileURLWithPath: artifactPath)
                .appendingPathComponent("metadata.bin")
            let metadata = try Data(contentsOf: metadataPath)
            let zipFunctions = MetadataDecoder().decode(metadata).filter {
                $0.kind == .function && $0.fqName == "kotlin.collections.zip"
            }
            let pairZipFunctions = zipFunctions.filter { $0.arity == 1 }
            let transformZipFunctions = zipFunctions.filter { $0.arity == 2 }
            #expect(!pairZipFunctions.isEmpty, "Fresh stdlib metadata should contain pair-returning zip overloads")
            #expect(!transformZipFunctions.isEmpty, "Fresh stdlib metadata should contain transform zip overloads")
            #expect(pairZipFunctions.allSatisfy { $0.isInfix }, "Pair-returning zip overloads should be infix")
            #expect(transformZipFunctions.allSatisfy { !$0.isInfix }, "Transform zip overloads must remain non-infix")
        }

        let options = CompilerOptions(
            moduleName: "IterableZip",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: !fromSource
        )
        #expect(options.includeStdlib == fromSource)
        #expect(options.stdlibLibraryPath == artifactPath)

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stdout == "(1, 3), (2, 4)\n(1, 3), (2, 4)\n(1, 4), (2, 5)\n1:4, 2:5\n")
    }
}
