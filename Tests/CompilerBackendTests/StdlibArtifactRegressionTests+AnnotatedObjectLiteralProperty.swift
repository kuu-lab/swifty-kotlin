@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2198: annotated anonymous-object properties compile, link, and read
    /// their stored fields through both stdlib surfaces and optimization levels.
    @Test(arguments: [false, true], [0, 2])
    func testAnnotatedObjectLiteralPropertyAcrossStdlibSurfaces(
        useArtifact: Bool,
        optimization: Int
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let artifact = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = try diffCaseSource("annotated_object_literal_property.kt", file: #filePath)

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU2198AnnotatedObjectLiteralProperty",
                outputPath: outputBase,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifact
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let surface = useArtifact ? "fresh .kklib" : "source"
            let route = "\(surface), O\(optimization)"
            #expect(result.exitCode == 0, "\(route): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(route): \(result.stderr)")
            #expect(result.stdout == "0\n1\n2\n3\n4\n", "\(route): \(String(reflecting: result.stdout))")
        }
    }
}
