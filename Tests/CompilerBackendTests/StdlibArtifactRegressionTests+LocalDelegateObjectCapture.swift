@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2949: an anonymous object (or local class) capturing a delegated
    /// local must re-register it as delegate storage, not a boxed cell, so
    /// member-body writes dispatch `setValue` and reads dispatch `getValue`.
    @Test
    func testLocalDelegateCaptureInAnonymousObjectMember() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("local_delegate_object_literal_capture.kt")
        let surfaces: [(name: String, libraryPath: String?)] = [
            ("source", nil),
            ("fresh .kklib", artifactPath),
        ]
        let expected = "OK\n42\n14\n9|0->9;\nLC\n11\n"

        for surface in surfaces {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let outputPath = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "LocalDelegateObjectLiteralCapture",
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
