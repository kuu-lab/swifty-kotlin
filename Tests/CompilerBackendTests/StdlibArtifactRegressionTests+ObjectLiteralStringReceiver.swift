@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2050: anonymous members must capture the selected String receiver.
    @Test
    func testObjectLiteralImplicitStringReceiverAcrossStdlibSurfaces() throws {
        let cases = [
            ("object_literal_implicit_string_receiver.kt", "65\n"),
            ("object_literal_nested_string_receiver.kt", "true\n65\n67\n66\n68\nfalse\n69\n70\n74\n72\n90\n75\n76\n1\n"),
        ]
        let artifactPath = try Self.buildStdlibArtifact()
        for (fileName, expected) in cases {
            let source = try diffCaseSource(fileName)
            for (surface, libraryPath) in [("source", nil), ("artifact", artifactPath)] {
                for optLevel in [OptimizationLevel.O0, .O2] {
                    try withTemporaryFile(contents: source) { inputPath in
                        let outputBase = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString).path
                        defer { try? FileManager.default.removeItem(atPath: outputBase) }
                        let context = try runCodegenPipeline(
                            inputPath: inputPath,
                            moduleName: "ObjectLiteralStringReceiver",
                            outputPath: outputBase,
                            optLevel: optLevel,
                            allowDefaultStdlibLibrary: false,
                            stdlibLibraryPath: libraryPath
                        )
                        try assertNoDiagnosticErrors(context)
                        try LinkPhase().run(context)
                        let result = try CommandRunner.run(executable: outputBase, arguments: [])
                        let route = "\(fileName), \(surface), \(optLevel)"
                        #expect(result.exitCode == 0, "\(route): \(result.stderr)")
                        #expect(result.stderr.isEmpty, "\(route): \(result.stderr)")
                        #expect(result.stdout == expected, "\(route): \(String(reflecting: result.stdout))")
                    }
                }
            }
        }
    }
}
