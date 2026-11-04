@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// Invoking a possibly-null function value without `?.invoke`/`!!` is an
/// unsafe call: `f()` on `f: (() -> Unit)?` is rejected even though the
/// structural function type resolves — the same rejection applies to a
/// type parameter whose bound is a nullable function type (`c(t)` on
/// `c: F` where `F : ((T) -> R)?`) and to explicit `x.invoke(...)` forms
/// (KUU-4138). Safe calls, `!!`, and stable `!= null` narrowings keep
/// working.
@Suite
struct NullableFunctionValueInvocationTests {
    @Test(arguments: [
        // Bare call on a nullable function-typed value.
        "fun bad(f: (() -> Unit)?) = f()",
        "fun bad(f: ((Int) -> Int)?) = f(3)",
        "fun bad() { val f: (() -> Unit)? = null; f() }",
        // Explicit `.invoke` on a nullable function-typed value.
        "fun bad(f: (() -> Unit)?) = f.invoke()",
        // Type parameter bounded by a nullable function type (KUU-4087 made
        // these reach the invoke path; the bound keeps them nullable).
        "fun <T, R, F : ((T) -> R)?> bad(t: T, c: F): R = c(t)",
        "fun <T, R, F : ((T) -> R)?> bad(t: T, c: F): R = c.invoke(t)",
        "fun <T, R, G : ((T) -> R)?, F : G> bad(t: T, c: F): R = c(t)",
        "fun <T, R, F> bad(t: T, c: F): R where F : ((T) -> R)? = c(t)",
        // Nullable function value produced by an indexing expression.
        "fun bad(a: MutableList<(() -> Unit)?>) = a[0]()",
    ])
    func rejectsUnsafeNullableFunctionValueInvocation(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" },
            "Expected SEMA-0026 for unsafe nullable invoke: \(source)\n\(ctx.diagnostics.diagnostics)"
        )
    }

    @Test(arguments: [
        // Safe call forms.
        "fun ok(f: (() -> Unit)?) = f?.invoke()",
        "fun <T, R, F : ((T) -> R)?> ok(t: T, c: F): R? = c?.invoke(t)",
        // `!!` assertion.
        "fun ok(f: (() -> Unit)?) = f!!()",
        "fun <T, R, F : ((T) -> R)?> ok(t: T, c: F): R = c!!(t)",
        // Smart casts on stable locals and parameters.
        "fun ok(f: (() -> Unit)?) { if (f != null) f() }",
        "fun ok() { var f: (() -> Unit)? = { }; if (f != null) f() }",
        "fun <T, R, F : ((T) -> R)?> ok(t: T, c: F): R? { if (c != null) return c(t); return null }",
        "fun ok(f: (() -> Unit)?) { if (f != null) f.invoke() }",
        // Non-nullable bound keeps the KUU-4087 invoke path working.
        "fun <T, R, F : (T) -> R> ok(t: T, c: F): R = c(t)",
        "fun <T, R, F : (T) -> R> ok(t: T, c: F): R = c.invoke(t)",
        // Non-nullable function values are unaffected.
        "fun ok(f: () -> Unit) = f()",
        "fun ok(f: () -> Unit) = f.invoke()",
    ])
    func acceptsNullSafeFunctionValueInvocation(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected acceptance: \(source)\n\(ctx.diagnostics.diagnostics)")
    }
}
