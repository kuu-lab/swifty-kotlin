@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct JavaUtilArraysHashCodeTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixture(_ name: String) -> URL {
        repository
            .appendingPathComponent("Scripts/reference_cases/KUU-2388")
            .appendingPathComponent(name)
    }

    private func compileAndRun(
        _ inputNames: [String],
        expectedOutput: String,
        moduleName: String,
        fromSource: Bool,
        optimization: Int
    ) throws {
        let stdlibArtifact = fromSource ? nil : try StdlibArtifactRegressionTests.buildStdlibArtifact()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: output) }

        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: inputNames.map { fixture($0).path },
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: stdlibArtifact,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: moduleName)

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Execution failed: \(result.stderr)")
        #expect(result.stdout == expectedOutput)
    }

    @Test(arguments: [0, 2])
    func pinnedKotlinDataClassArrayHashCodeTestPassesFromSource(optimization: Int) throws {
        try compileAndRun(
            ["array.kt", "array_main.kt"],
            expectedOutput: "OK",
            moduleName: "KUU2388PinnedArrayHashCode",
            fromSource: true,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func pinnedKotlinDataClassArrayHashCodeTestPassesFromFreshArtifact(optimization: Int) throws {
        try compileAndRun(
            ["array.kt", "array_main.kt"],
            expectedOutput: "OK",
            moduleName: "KUU2388PinnedArrayHashCode",
            fromSource: false,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func minimalFullyQualifiedReproductionPassesFromSource(optimization: Int) throws {
        try compileAndRun(
            ["hashcode_minimal.kt"],
            expectedOutput: "OK",
            moduleName: "KUU2388MinimalArrayHashCode",
            fromSource: true,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func minimalFullyQualifiedReproductionPassesFromFreshArtifact(optimization: Int) throws {
        try compileAndRun(
            ["hashcode_minimal.kt"],
            expectedOutput: "OK",
            moduleName: "KUU2388MinimalArrayHashCode",
            fromSource: false,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func fullyQualifiedAndStaticImportCallsMatchJvmHashesFromSource(optimization: Int) throws {
        try compileAndRun(
            ["hashcode_contracts.kt"],
            expectedOutput: "1\n1\n32\n32\n30817\n30817\n28891\n28891\n0\n0\nfill:OK\n",
            moduleName: "KUU2388ArrayHashCodeContracts",
            fromSource: true,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func fullyQualifiedAndStaticImportCallsMatchJvmHashesFromFreshArtifact(optimization: Int) throws {
        try compileAndRun(
            ["hashcode_contracts.kt"],
            expectedOutput: "1\n1\n32\n32\n30817\n30817\n28891\n28891\n0\n0\nfill:OK\n",
            moduleName: "KUU2388ArrayHashCodeContracts",
            fromSource: false,
            optimization: optimization
        )
    }

    @Test(arguments: [true, false])
    func unsupportedLongArrayOverloadRemainsUnresolved(fromSource: Bool) throws {
        let stdlibArtifact = fromSource ? nil : try StdlibArtifactRegressionTests.buildStdlibArtifact()
        let source = "fun main() { java.util.Arrays.hashCode(longArrayOf(1L)) }"
        try withTemporaryFile(contents: source) { input in
            let result = makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "KUU2388UnsupportedArrayHashCode",
                inputs: [input],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .executable,
                target: defaultTargetTriple(),
                includeStdlib: fromSource,
                stdlibLibraryPath: stdlibArtifact,
                allowDefaultStdlibLibrary: false
            ))
            #expect(result.exitCode != 0)
            #expect(result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
        }
    }
}
