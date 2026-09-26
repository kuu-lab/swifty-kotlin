#if canImport(Testing)
@testable import CompilerCore
import Testing

/// A lambda parameter (`it` or a named parameter) used as a `when` subject
/// must be smart-cast in `is` branches just like a regular function
/// parameter. The lambda parameter's symbol is a synthetic ID that is never
/// registered in the symbol table, which used to make
/// `TypeCheckHelpers.isStableLocalSymbol` treat it as unstable and skip the
/// narrowing entirely (while the same synthetic ID was already treated as
/// stable by the `if (it is T)` narrowing path in DataFlow/Analysis.swift's
/// `resolveLocalVariable`).
@Suite
struct WhenSubjectSmartCastTests {
    @Test func testLambdaParameterWhenSubjectSmartCast() throws {
        let source = """
        sealed interface Shape
        class Circle(val r: Double) : Shape
        class Rect(val w: Double, val h: Double) : Shape

        fun describeAll(shapes: List<Shape>): List<String> {
            val byIt = shapes.map { when (it) { is Circle -> "c${it.r}"; is Rect -> "r${it.w}x${it.h}" } }
            val byNamed = shapes.map { s -> when (s) { is Circle -> "c${s.r}"; is Rect -> "r${s.w}x${s.h}" } }
            return byIt + byNamed
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExtensionReceiverThisWhenSubjectSmartCastAndExhaustiveness() throws {
        let source = """
        sealed class Result {
            data class Ok(val v: Int) : Result()
            data class Err(val msg: String) : Result()
        }
        fun Result.text() = when (this) { is Result.Ok -> "ok$v"; is Result.Err -> "err:$msg" }

        sealed class Top
        class A1(val a: Int) : Top()
        class B1(val b: String) : Top()
        fun Top.t() = when (this) { is A1 -> "a$a"; is B1 -> "b$b" }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
