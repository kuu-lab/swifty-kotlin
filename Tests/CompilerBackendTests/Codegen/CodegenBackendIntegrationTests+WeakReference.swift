@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendWeakReferenceTests {
    private func runExecutablePipeline(
        inputPath: String,
        moduleName: String,
        outputPath: String,
        allowDefaultStdlibLibrary: Bool = true
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
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
        expected: String,
        allowDefaultStdlibLibrary: Bool = true
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runExecutablePipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
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

    // KUU-1666: immediate primitive words are live values, and the class
    // member keeps `.value` typed as T? while the legacy extension import
    // remains available. Exercise both source injection and a freshly built
    // precompiled stdlib artifact.
    @Test(arguments: [false, true])
    func testCodegenWeakReferenceImmediateAndTypedReferents(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        class Box(val n: Int)

        fun main() {
            println(WeakReference(0).value)
            println(WeakReference(42).value)
            println(WeakReference(-1).value)
            println(WeakReference(Int.MIN_VALUE).value)
            println(WeakReference(Int.MAX_VALUE).value)
            println(WeakReference(42L).value)
            println(WeakReference(-7L).value)
            println(WeakReference(Long.MAX_VALUE).value)
            println(WeakReference(false).value)
            println(WeakReference(true).value)
            println(WeakReference('z').value)
            println(WeakReference(1.5f).value)
            println(WeakReference(1.5).value)
            println(WeakReference("hello").value)

            val boxRef = WeakReference(Box(7))
            println(boxRef.value?.n)
            println(boxRef.get()?.n)

            val arrayRef = WeakReference(arrayOf(5, 9))
            println(arrayRef.value?.get(0))
            println(arrayRef.get()?.get(1))

            val first = WeakReference("first")
            val second = WeakReference("second")
            val star: WeakReference<*> = second
            println(star.value is String)
            println(star.value)
            first.clear()
            println(first.value)
            println(first.get())
            println(second.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceImmediateAndTypedReferents",
            expected: """
            0
            42
            -1
            -2147483648
            2147483647
            42
            -7
            9223372036854775807
            false
            true
            z
            1.5
            1.5
            hello
            7
            7
            5
            9
            true
            second
            null
            null
            second
            """ + "\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
