@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2066: omitted type arguments must survive producer library emission.
    @Test
    func testInferredEnumValuesProducerAcrossStdlibSurfaces() throws {
        let artifact = try Self.buildStdlibArtifact()
        let cases = [
            ("inferred", "inline fun <reified T : Enum<T>> enumArray(): Array<T> = enumValues()", true),
            ("explicit", "inline fun <reified T : Enum<T>> enumArray(): Array<T> = enumValues<T>()", true),
            ("nonEnum", "fun invalid(): Array<String> = enumValues()", false),
        ]
        for library in [nil, artifact] as [String?] {
            for level in [OptimizationLevel.O0, .O2] {
                for (name, source, accepted) in cases {
                    try withTemporaryFile(contents: source) { path in
                        let output = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString).path
                        defer { try? FileManager.default.removeItem(atPath: output + ".kklib") }
                        let ctx = CompilationContext(options: CompilerOptions(
                            moduleName: "EnumValuesProducer_\(name)", inputs: [path], outputPath: output,
                            emit: .library, target: defaultTargetTriple(), optLevel: level,
                            includeStdlib: library == nil, stdlibLibraryPath: library,
                            allowDefaultStdlibLibrary: false
                        ), sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner())
                        try runSema(ctx)
                        #expect(ctx.diagnostics.hasError == !accepted,
                                "\(name), artifact=\(library != nil), \(level): \(ctx.diagnostics.diagnostics)")
                        if accepted {
                            try BuildKIRPhase().run(ctx)
                            try LoweringPhase().run(ctx)
                            try assertNoDiagnosticErrors(ctx)
                            try CodegenPhase().run(ctx)
                            try assertNoDiagnosticErrors(ctx)
                            #expect(FileManager.default.fileExists(atPath: output + ".kklib/manifest.json"))
                        } else {
                            #expect(ctx.diagnostics.diagnostics.contains {
                                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0002"
                            })
                        }
                    }
                }
            }
        }
    }
}
