@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2218: enum `values()` is visible from enum members and companion
    /// initializers across source and serialized stdlib configurations.
    @Test
    func testUnqualifiedEnumValuesAcrossStdlibSurfaces() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/enum_unqualified_values.kt"
        ), encoding: .utf8)
        let expected = "OK\n"

        for (surface, library) in [("Source", nil as String?), ("Library", artifactPath)] {
            for optimization in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "EnumValuesLexicalLookup\(surface)\(optimization)",
                        outputPath: output,
                        optLevel: optimization,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: library
                    )
                    try assertNoDiagnosticErrors(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: output, arguments: [])
                    #expect(result.exitCode == 0, "\(surface) \(optimization): \(result.stderr)")
                    #expect(result.stderr.isEmpty, "\(surface) \(optimization)")
                    #expect(result.stdout == expected, "\(surface) \(optimization)")
                }
            }
        }
    }
}
