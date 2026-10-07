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

    // KUU-1363: `WeakReference.value` is `get() = this.get()` in bundled
    // kotlin/native/ref/Weak.kt. The frontend used to truncate the accessor's
    // `= expr` body at the `get(` member call, so the compiled getter returned
    // the WeakReference box itself instead of the referent. This test runs the
    // public contract end to end: value/get return the referent before
    // clear(), null after it, on both parameterized and star-projected
    // references, and clearing one reference must not affect another.
    // (Member calls on a WeakReference<*>-typed reference hit an unrelated
    // kklib-route bound-check gap, so the star-projected handle only reads
    // `value`; the shared box is cleared through `second`.)
    @Test
    func testCodegenWeakReferenceValueReturnsReferentThenNull() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        fun main() {
            val first = WeakReference("x")
            val second = WeakReference("y")
            println(first.get())
            println(first.value)
            println(second.value)
            first.clear()
            println(first.get())
            println(first.value)
            println(second.get())
            val star: WeakReference<*> = second
            println(star.value)
            second.clear()
            println(star.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceValueReturnsReferent",
            expected: "x\nx\ny\nnull\nnull\ny\ny\nnull\n"
        )
    }

    // KUU-1467: A runtime-materialized String must round-trip through both
    // WeakReference accessors, and clear() must drop that same referent.
    @Test
    func testCodegenWeakReferencePreservesRuntimeStringReferent() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        fun main() {
            val s = "hello".toString()
            val w = WeakReference(s)
            println(w.value == s)
            println(w.value is String)
            println(w.value)
            println(w.get() == s)
            println(w.get() is String)
            println(w.get())
            w.clear()
            println(w.value == null)
            println(w.get() == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceRuntimeStringReferent",
            expected: "true\ntrue\nhello\ntrue\ntrue\nhello\ntrue\ntrue\n"
        )
    }
}
#endif
