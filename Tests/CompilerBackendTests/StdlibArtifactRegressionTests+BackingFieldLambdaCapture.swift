@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2250: a getter's backing field must retain its owning receiver in a lambda.
    @Test
    func testGetterBackingFieldCaptureAcrossStdlibSurfaces() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("kuu_2250_getter_field_lambda_capture.kt")
        let surfaces: [(name: String, libraryPath: String?)] = [
            ("source", nil),
            ("fresh .kklib", artifactPath),
        ]
        let expected = "OK\nOK\nOK\nOK\nO\nOK\nmember\n"

        for surface in surfaces {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let outputPath = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "GetterBackingFieldLambdaCapture",
                        outputPath: outputPath,
                        optLevel: optLevel,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: surface.libraryPath
                    )
                    let route = "\(surface.name), \(optLevel)"
                    try assertNoDiagnosticErrors(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: outputPath, arguments: [])
                    #expect(result.exitCode == 0, "\(route): \(result.stderr)")
                    #expect(result.stderr.isEmpty, "\(route): \(result.stderr)")
                    #expect(result.stdout == expected, "\(route): \(String(reflecting: result.stdout))")
                }
            }
        }
    }
}
