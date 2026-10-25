@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2039: stable JVM category numbers and code point boundaries on both surfaces.
    @Test
    func testJavaCharacterUnicodeAcrossStdlibSurfaces() throws {
        let source = try diffCaseSource("java_character_unicode.kt", file: #filePath)
        // Kotlin/JVM 2.3.10, JDK API 17 reference output, in fixture order.
        let numericOutput = [6, 7, 16] + [1, 1, 1, 1, 1, 2, 2, 2, 2]
            + Array(0...16) + Array(18...30) + [19, 0, 0, 1, 2, 6, 16, 18, 0]
        let expected = (numericOutput.map(String.init)
            + Array(repeating: "true", count: 10) + Array(repeating: "false", count: 10)
            + ["true", "true", "true", "false", "true", "65", "0"]
            + [
                "true", "true", "true", "true", "true", "true", "false",
                "true", "true", "true", "A", "a", "65", "97", "A", "65",
                "9", "9", "-1", "-1", "9", "z", "true", "9", "10", "50",
                "-2", "-1", "true", "true", "false", "true", "true", "true",
            ])
            .joined(separator: "\n") + "\n"
        let artifactPath = try Self.buildStdlibArtifact()
        for (surface, libraryPath) in [("source", nil), ("artifact", artifactPath)] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let outputBase = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: outputBase) }
                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "KUU2039_\(surface)_\(optLevel.rawValue)",
                        outputPath: outputBase,
                        optLevel: optLevel,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: libraryPath
                    )
                    try assertNoDiagnosticErrors(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: outputBase, arguments: [])
                    #expect(result.exitCode == 0, "\(surface) \(optLevel): \(result.stderr)")
                    #expect(result.stderr.isEmpty, "\(surface) \(optLevel): \(result.stderr)")
                    #expect(result.stdout == expected, "\(surface) \(optLevel): \(String(reflecting: result.stdout))")
                }
            }
        }
    }
}
