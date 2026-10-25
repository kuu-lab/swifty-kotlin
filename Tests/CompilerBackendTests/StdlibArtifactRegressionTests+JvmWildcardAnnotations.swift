@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testJvmWildcardAnnotationsAcrossStdlibSurfaces() throws {
        let source = try diffCaseSource("jvm_wildcard_annotations.kt", file: #filePath)
        let artifact = try Self.buildStdlibArtifact()
        let expected = "true\nfalse\ntrue\nkotlin.jvm.JvmWildcard\nkotlin.jvm.JvmSuppressWildcards\nvalue\n"

        for library in [nil, artifact] as [String?] {
            try withTemporaryFile(contents: source) { input in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: input,
                    moduleName: "JvmWildcardAnnotations",
                    outputPath: output,
                    optLevel: .O0,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: library
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected)
            }
        }

        try withTemporaryFile(contents: "import kotlin.jvm.JvmWildcard\n@JvmWildcard class Invalid") { input in
            let context = makeCompilationContext(
                inputs: [input],
                includeStdlib: false,
                stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            do {
                try runSema(context)
            } catch {
                // The annotation is restricted to types, including after import.
            }
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-ANNOTATION-TARGET")
        }
    }
}
