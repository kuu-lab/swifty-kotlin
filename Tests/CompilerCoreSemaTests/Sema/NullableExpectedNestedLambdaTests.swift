#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-4469: an unannotated inner lambda returned through a generic
/// higher-order call must receive its parameter types when the call's
/// expected result is a *nullable* function type. These cases pin the
/// behaviour on the `runSema`/`--stdlib-from-source` path, where the
/// substituted expected type previously failed to reach the inner lambda
/// and its parameters fell back to `Any` (SEMA-0473).
@Suite
struct NullableExpectedNestedLambdaTests {
    private func runSemaOn(_ source: String, includeStdlib: Bool) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: includeStdlib)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Each test asserts the expected diagnostics.
        }
        return ctx
    }

    @Test func nestedLambdaThroughGenericHOFGetsParameterTypes() {
        for includeStdlib in [false, true] {
            let ctx = runSemaOn("""
            fun <T, R> T.myLet(block: (T) -> R): R = block(this)
            fun sink(s: String) { }
            fun viaMyLet(f: ((String) -> Unit)): ((String, Int, Any) -> Unit)? =
                f.myLet { { cause, _, _ -> sink(cause) } }
            """, includeStdlib: includeStdlib)
            #expect(
                !ctx.diagnostics.hasError,
                "includeStdlib=\(includeStdlib) diagnostics: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error })"
            )
        }
    }

    @Test func innerLambdaCanInvokeOuterParameter() {
        // `f(cause)` requires `cause` to infer as String from the expected
        // `(String, Int, Any) -> Unit` — it errors when inference drops it.
        for includeStdlib in [false, true] {
            let ctx = runSemaOn("""
            fun <T, R> T.myLet(block: (T) -> R): R = block(this)
            fun viaMyLet(f: ((String) -> Unit)): ((String, Int, Any) -> Unit)? =
                f.myLet { { cause, _, _ -> f(cause) } }
            """, includeStdlib: includeStdlib)
            #expect(
                !ctx.diagnostics.hasError,
                "includeStdlib=\(includeStdlib) diagnostics: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error })"
            )
        }
    }

    @Test func nestedLambdaThroughSafeCallGetsParameterTypes() {
        for includeStdlib in [false, true] {
            let ctx = runSemaOn("""
            fun <T, R> T.myLet(block: (T) -> R): R = block(this)
            fun sink(s: String) { }
            fun viaSafeLet(f: ((String) -> Unit)?): ((String, Int, Any) -> Unit)? =
                f?.myLet { { cause, _, _ -> sink(cause) } }
            """, includeStdlib: includeStdlib)
            #expect(
                !ctx.diagnostics.hasError,
                "includeStdlib=\(includeStdlib) diagnostics: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error })"
            )
        }
    }

    @Test func nonNullExpectedTypeAlsoWorks() {
        let ctx = runSemaOn("""
        fun <T, R> T.myLet(block: (T) -> R): R = block(this)
        fun sink(s: String) { }
        fun viaMyLet(f: ((String) -> Unit)): (String, Int, Any) -> Unit =
            f.myLet { { cause, _, _ -> sink(cause) } }
        """, includeStdlib: false)
        #expect(
            !ctx.diagnostics.hasError,
            "diagnostics: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error })"
        )
    }

    @Test func nestedLambdaThroughSafeCallPropertyInitializerGetsParameterTypes() {
        // KUU-4201 (kotlinx.coroutines BufferedChannel): the same
        // `receiver?.let { ... }` shape sits in a *property initializer*
        // whose declared type is a nullable function type, and the let
        // block is an annotated lambda returning an unannotated inner
        // lambda whose parameters must come from the expected type —
        // otherwise the call's result fails its upper bound with
        // TYPE-0001.
        for includeStdlib in [false, true] {
            let ctx = runSemaOn("""
            fun <T, R> T.myLet(block: (T) -> R): R = block(this)
            typealias Ctor = (Int, Any?, Any?) -> (Any?, Boolean, Any?) -> Unit
            class Holder(val hook: (() -> Unit)?) {
                val ctor: Ctor? = hook?.myLet {
                    { a: Int, _: Any?, element: Any? ->
                        { _, _, _ ->
                            if (element != null) hook()
                        }
                    }
                }
            }
            """, includeStdlib: includeStdlib)
            #expect(
                !ctx.diagnostics.hasError,
                "includeStdlib=\(includeStdlib) diagnostics: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error })"
            )
        }
    }

    @Test func unannotatedLambdaWithoutExpectedTypeStillRejects() {
        // Parity with kotlinc: `val g = { unannotated, params -> ... }`
        // inside a lambda body carries no expected type, so every compiler
        // must reject it — a pass here would mean the expected type leaks
        // into a scope Kotlin does not define.
        let ctx = runSemaOn("""
        fun <T, R> T.myLet(block: (T) -> R): R = block(this)
        fun sink(s: String) { }
        fun viaMyLet(f: ((String) -> Unit)): ((String, Int, Any) -> Unit)? =
            f.myLet { val g = { cause, _, _ -> sink(cause) }; g }
        """, includeStdlib: false)
        #expect(
            ctx.diagnostics.hasError,
            "expected rejection; diagnostics: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
