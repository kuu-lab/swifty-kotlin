@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct JavaUtilArraysSortTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixture(_ name: String) throws -> URL {
        repository
            .appendingPathComponent("Scripts/reference_cases/KUU-1859")
            .appendingPathComponent(name)
    }

    private func expectedOutput(_ name: String) throws -> String {
        try String(contentsOf: fixture(name), encoding: .utf8)
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
            inputs: try inputNames.map { try fixture($0).path },
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

    @Test(arguments: [true, false], [0, 2])
    func minimalStaticImportReproductionMatchesExpectedOutput(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(
            ["arrays_sort_minimal.kt"],
            expectedOutput: try expectedOutput("arrays_sort_minimal.expected"),
            moduleName: "KUU1859ArraysSortMinimal",
            fromSource: fromSource,
            optimization: optimization
        )
    }

    @Test(arguments: [true, false], [0, 2])
    func staticImportAndFqnCoverArrayAndExceptionContracts(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(
            ["arrays_sort_contracts.kt"],
            expectedOutput: try expectedOutput("arrays_sort_contracts.expected"),
            moduleName: "KUU1859ArraysSortContracts",
            fromSource: fromSource,
            optimization: optimization
        )
    }

    @Test(arguments: [true, false], [0, 2])
    func pinnedMedianConsumerRunsWithoutSourceChanges(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(
            ["Median.kt", "Main.kt"],
            expectedOutput: try expectedOutput("median.expected"),
            moduleName: "KUU1859Median",
            fromSource: fromSource,
            optimization: optimization
        )
    }
}
