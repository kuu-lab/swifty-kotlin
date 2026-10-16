@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2233: BigDecimal's Number conversions survive a fresh .kklib and O0/O2 consumers.
    @Test(arguments: [0, 2])
    func testBigDecimalNumberConversionsThroughFreshStdlibArtifact(optLevelRawValue: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("big_decimal_number_conversions.kt")
        let expected = try CompilerTestSupport.repositoryFileSource(
            "Scripts/diff_cases/big_decimal_number_conversions.expected"
        )

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU2233_BigDecimal_\(optLevel.rawValue)",
                outputPath: outputBase,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(optLevel): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(optLevel): \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                "Unexpected output at \(optLevel): \(String(reflecting: result.stdout))"
            )
        }
    }
}
