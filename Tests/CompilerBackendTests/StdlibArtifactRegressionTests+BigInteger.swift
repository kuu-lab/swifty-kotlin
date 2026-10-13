@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2010: value equality must survive source injection and metadata import.
    /// Expected output was measured with Kotlin 2.3.10 and JDK 17.
    /// Multiplication-derived cases remain in the diff fixtures; KUU-2026 blocks them.
    @Test
    func testBigIntegerEqualityAcrossStdlibSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let artifactPath = try Self.buildStdlibArtifact()

        for caseName in ["big_integer_value_equality"] {
            let caseBase = repoRoot.appendingPathComponent("Scripts/diff_cases/\(caseName)")
            let expected = try String(contentsOf: caseBase.appendingPathExtension("expected"), encoding: .utf8)
            for (surface, libraryPath) in [("source", nil), ("artifact", artifactPath)] {
                for optLevel in [OptimizationLevel.O0, .O2] {
                    let outputBase = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: outputBase) }
                    let context = try runCodegenPipeline(
                        inputPath: caseBase.appendingPathExtension("kt").path,
                        moduleName: "BigIntegerEquality",
                        outputPath: outputBase,
                        optLevel: optLevel,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: libraryPath
                    )
                    try assertNoDiagnosticErrors(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: outputBase, arguments: [])
                    let route = "\(caseName), \(surface), \(optLevel)"
                    #expect(result.exitCode == 0, "\(route): \(result.stderr)")
                    #expect(result.stderr.isEmpty, "\(route): \(result.stderr)")
                    #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected, "\(route)")
                }
            }
        }
    }
}
