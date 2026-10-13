@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true])
    func testJavaThreadLocalInitialValueAndGet(sourceMode: Bool) throws {
        let artifact = sourceMode ? nil : try Self.buildStdlibArtifact()
        for (caseName, expected) in [
            ("java_thread_local_initial_value.kt", "value\nvalue\n"),
            ("java_thread_local_contracts.kt", "value\nvalue\nvalue\n1\nprotected\nnull\nnull\n1\nfallback\nfallback\n1\nnull\ndirect\ndirect\n42\n42\n42\nreset\n"),
        ] where !sourceMode || caseName == "java_thread_local_initial_value.kt" {
            // The exact reproducer owns the four-mode matrix. Broader
            // contracts exercise the shared artifact without rechecking all
            // bundled source bodies for each control case.
            let source = try diffCaseSource(caseName, file: #filePath)
            try withTemporaryFile(contents: source) { path in
                for level in [OptimizationLevel.O0, .O2] {
                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: output) }
                    let options = CompilerOptions(
                        moduleName: "JavaThreadLocalConsumer", inputs: [path],
                        outputPath: output, emit: .executable,
                        target: defaultTargetTriple(), optLevel: level,
                        includeStdlib: sourceMode, stdlibLibraryPath: artifact,
                        allowDefaultStdlibLibrary: false
                    )
                    let ctx = CompilationContext(
                        options: options, sourceManager: SourceManager(),
                        diagnostics: DiagnosticEngine(), interner: StringInterner()
                    )
                    try runToKIR(ctx)
                    try LoweringPhase().run(ctx)
                    try CodegenPhase().run(ctx)
                    try LinkPhase().run(ctx)
                    let result = try CommandRunner.run(executable: output, arguments: [])
                    #expect(result.exitCode == 0)
                    #expect(result.stderr.isEmpty)
                    #expect(result.stdout == expected)
                    let sema = try #require(ctx.sema)
                    for method in ["get", "initialValue"] {
                        let fq = ["java", "lang", "ThreadLocal", method].map(ctx.interner.intern)
                        let symbol = try #require(sema.symbols.lookup(fqName: fq))
                        let signature = try #require(sema.symbols.functionSignature(for: symbol))
                        #expect(sema.types.nullability(of: signature.returnType) == .platformType)
                    }
                }
            }
        }
        if let artifact {
            for (source, code) in [
                ("fun probe(local: ThreadLocal<String>) { local.initialValue() }", "KSWIFTK-SEMA-0041"),
                ("class Local : ThreadLocal<String>() { override fun initialValue(): Int = 1 }", "KSWIFTK-SEMA-OVERRIDE-RETURN"),
                ("class Local : ThreadLocal<String>() { private override fun initialValue(): String = null!! }", "KSWIFTK-SEMA-VISIBILITY"),
            ] {
                try withTemporaryFile(contents: source) { path in
                    let ctx = makeCompilationContext(
                        inputs: [path], includeStdlib: false, stdlibLibraryPath: artifact,
                        allowDefaultStdlibLibrary: false
                    )
                    try? runSema(ctx)
                    #expect(ctx.diagnostics.diagnostics.contains {
                        $0.severity == .error && $0.code == code
                    }, "Expected \(code), got: \(ctx.diagnostics.diagnostics)")
                }
            }
        }
    }
}
