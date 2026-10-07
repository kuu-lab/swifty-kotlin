#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-1368: an Elvis `?:` right-hand side is checked against the whole
/// expression's expected type when one exists, and against the LHS's
/// non-null type when it does not — the same rule kotlinc applies. Without
/// the LHS seed, a lambda RHS never binds its implicit `it`:
/// `g ?: { it.length }` on `g: ((String) -> Int)?` used to report
/// `KSWIFTK-SEMA-0022 Unresolved reference 'it'`.
@Suite
struct ElvisRhsLambdaContextualTypeTests {

    /// The ticket's minimal reproducer: inferred return position, so no
    /// contextual type exists and `it` must come from `g`'s function type.
    @Test func elvisRhsLambdaBindsImplicitItFromNullableFunctionTypeLhs() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt0
            fun f(g: ((String) -> Int)?) = g ?: { it.length }
            fun main() {
                val g: ((String) -> Int)? = { it.length }
                println(f(g)("hello"))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// Mirrors the kotlinx-cli `ArgType.Choice` factory: the `it` inside the
    /// `find` predicate is the OUTER Elvis-RHS lambda's parameter (the inner
    /// lambda declares `e` explicitly), and the nested `?: throw` Elvis sits
    /// inside that same lambda.
    @Test func elvisRhsLambdaNestedFindAndInnerThrowElvis() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt1
            fun <T> pick(toVariant: ((String) -> T)?, toString: (T) -> String, values: List<T>): (String) -> T {
                return toVariant ?: {
                    values.find { e -> toString(e).equals(it, ignoreCase = true) }
                        ?: throw IllegalArgumentException("No enum constant $it")
                }
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// Explicit lambda parameters must keep working under the seeded type,
    /// and a zero-parameter function type accepts a `it`-free lambda.
    @Test func elvisRhsLambdaWithExplicitAndZeroParams() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt2
            fun binary(g: ((String, Int) -> Int)?) = g ?: { a, b -> a.length + b }
            fun nullary(g: (() -> String)?) = g ?: { "x" }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// A local initializer has no declared expected type either: `it` must
    /// still bind from `g`, and a nullable declared function type keeps
    /// working through `val h: ((String) -> Int)? = ...`.
    @Test func elvisRhsLambdaInInitializerPositions() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt3
            fun h(g: ((String) -> Int)?): ((String) -> Int)? = g ?: { it.length }
            fun local(g: ((String) -> Int)?): Int {
                val inferred = g ?: { it.length }
                val declared: ((String) -> Int)? = g ?: { it.length }
                return inferred("a")
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// The LHS seed is not lambda-specific: `x ?: 0` on `x: Byte?` narrows
    /// the literal to Byte, so the whole Elvis types as Byte and satisfies a
    /// declared `Byte` target — kotlinc infers `Byte` here as well.
    @Test func elvisRhsIntegerLiteralNarrowsToLhsElementType() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt4
            fun narrow(b: Byte?): Byte {
                val z: Byte = b ?: 0
                return z
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// Parity: when a contextual expected type IS present it wins over the
    /// LHS function type — `Any` cannot bind `it`, so kotlinc and kswiftc
    /// both report the reference unresolved.
    @Test func elvisRhsLambdaWithNonFunctionExpectedTypeStillRejects() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt5
            fun g(): ((String) -> Int)? = null
            val topLevel: Any = g() ?: { it.length }
            fun viaReturn(g: ((String) -> Int)?): Any = g ?: { it.length }
            """
        ])
        try runSema(ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 2, in: ctx)
    }

    /// Parity: a nullable non-function LHS (`Int?`) provides no parameter
    /// type for `it` — kotlinc rejects `g ?: { it.length }` the same way.
    @Test func elvisRhsLambdaWithNonFunctionLhsStillRejects() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt6
            fun f(g: Int?) = g ?: { it.length }
            """
        ])
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    /// Parity: `null`'s `Nothing` LHS seeds no contextual type, so `it`
    /// stays unresolved — kotlinc reports `unresolved reference 'it'` too.
    @Test func elvisRhsLambdaWithNullLiteralLhsStillRejects() throws {
        let ctx = makeContextFromSources([
            """
            package elvisIt7
            val v = null ?: { it.length }
            """
        ])
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }
}
#endif
