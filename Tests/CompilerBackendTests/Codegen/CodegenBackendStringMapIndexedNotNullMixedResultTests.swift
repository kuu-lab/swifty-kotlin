@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendStringMapIndexedNotNullMixedResultTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test(arguments: [0, 2], [false, true])
    func preservesMixedResultValuesAndRuntimeTypes(optimization: Int, allowDefaultStdlibLibrary: Bool) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/string_map_indexed_not_null_mixed_char_int.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "StringMapIndexedNotNullMixedResult",
            expected: "7, 6\n7, 6\ntrue\ntrue\ntrue\ntrue\n7\n6\n7\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [0, 2], [false, true])
    func unchangedUpstreamDay01MatchesSamples(optimization: Int, allowDefaultStdlibLibrary: Bool) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let fixture = repoRoot.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/aoc-day01")
        let inputs = ["Day01.kt", "Main.kt"].map { fixture.appendingPathComponent($0).path }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: output) }
        var options = makeTestOptions(
            moduleName: "UpstreamDay01",
            inputs: inputs,
            outputPath: output,
            emit: .executable,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
        options.optLevel = optLevel
        let compilation = makeTestDriver().runForTesting(options: options)
        try assertCompilationSucceeded(compilation)
        let result = try CommandRunner.run(executable: output, arguments: [], timeout: 30)
        #expect(result.stdout == "142\n281\n")
        #expect(result.stderr.isEmpty)
    }
}
