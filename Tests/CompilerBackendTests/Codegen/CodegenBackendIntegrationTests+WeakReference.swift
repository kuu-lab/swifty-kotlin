@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendWeakReferenceTests {
    private func runExecutablePipeline(
        inputPath: String,
        moduleName: String,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runExecutablePipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    // KSP-1255: WeakReference(referred: T)'s constructor bridges straight to
    // the kk_weak_ref_create runtime factory (see CallLowerer's
    // isRuntimeFactoryConstructor). get() after clear() must observe the
    // referent as gone: the runtime's "no referent" sentinel is Any-erased
    // (kk_weak_ref_get returns runtimeNullSentinelInt, not bare 0), and a
    // regression here previously round-tripped back to Kotlin as a boxed
    // non-null Int(0) instead of null.
    @Test
    func testCodegenWeakReferenceGetReflectsClear() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference

        class Box(val n: Int)

        fun main() {
            val box = Box(42)
            val ref = WeakReference(box)
            println(ref.get()?.n)
            ref.clear()
            println(ref.get() == null)
            println(ref.get())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceClearReflectsNull",
            expected: "42\ntrue\nnull\n"
        )
    }
}
#endif
