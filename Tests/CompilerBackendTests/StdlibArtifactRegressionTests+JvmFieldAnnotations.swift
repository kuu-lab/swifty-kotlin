@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3068: default imports and field use-site targets resolve in both stdlib modes.
    @Test
    func testJvmFieldAnnotationsAcrossStdlibSurfaces() throws {
        let source = try diffCaseSource("jvm_field_annotations.kt", file: #filePath)
        let artifact = try Self.buildStdlibArtifact()

        for library in [nil, artifact] as [String?] {
            try withTemporaryFile(contents: source) { input in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: input,
                    moduleName: "JvmFieldAnnotations",
                    outputPath: output,
                    optLevel: .O0,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: library,
                    prepareTestStdlibCache: false
                )
                try assertNoDiagnosticErrors(context)
                let sema = try #require(context.sema)
                for name in ["Volatile", "Transient"] {
                    let annotation = MetadataAnnotationRecord(annotationFQName: "kotlin.jvm.\(name)")
                    #expect(resolvedAnnotationRetention(annotation, symbols: sema.symbols, interner: context.interner) == .source)
                }
                for (property, annotation) in [
                    ("implicitVolatile", "Volatile"), ("implicitTransient", "Transient"),
                    ("explicitVolatile", "Volatile"), ("explicitTransient", "Transient"),
                ] {
                    let symbol = try #require(sema.symbols.lookup(fqName: ["FieldFlags", property].map(context.interner.intern)))
                    #expect(sema.symbols.annotations(for: symbol).contains {
                        $0.annotationFQName == "kotlin.jvm.\(annotation)"
                    }, "\(property), artifact=\(library != nil): \(sema.symbols.annotations(for: symbol))")
                }
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == "5\n2\n3\n6\n")
            }

            let invalid = """
            @Volatile class BadVolatile
            @Transient fun badTransient() {}
            """
            try withTemporaryFile(contents: invalid) { input in
                let context = CompilerTestSupport.makeCompilationContext(
                    inputs: [input],
                    includeStdlib: library == nil,
                    stdlibLibraryPath: library,
                    allowDefaultStdlibLibrary: false
                )
                do {
                    try runSema(context)
                } catch {
                    // Both annotations are restricted to backing fields.
                }
                let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.count == 2, "\(errors)")
                #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }, "\(errors)")
            }
        }
    }
}
