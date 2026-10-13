@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2012: exact signed shifts must survive stdlib serialization and optimization.
    @Test
    func testBigIntegerShiftLeftAcrossStdlibSurfaces() throws {
        let source = try diffCaseSource("big_integer_shift_left.kt")
        let expected = """
        12
        -12
        4
        7
        -7
        0
        0
        0
        1267650600228229401496703205376
        -3802951800684688204490109616128
        -5
        -1
        -1
        -10
        1
        -100
        0
        -1
        0
        -1
        -18446744073709551616
        -1
        9223372036854775807
        2
        -2
        -21
        0
        overflow
        overflow

        """
        let artifactPath = try Self.buildStdlibArtifact()
        for (surface, libraryPath) in [("source", nil), ("artifact", artifactPath)] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let outputBase = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: outputBase) }
                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "KUU2012_\(surface)_\(optLevel.rawValue)",
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
                    #expect(
                        result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                        "Unexpected output using \(surface) at \(optLevel): \(String(reflecting: result.stdout))"
                    )
                }
            }
        }
    }
}
