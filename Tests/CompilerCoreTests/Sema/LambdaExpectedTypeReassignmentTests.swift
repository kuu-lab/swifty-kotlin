#if canImport(Testing)
@testable import CompilerCore
import Testing

/// A declared expected type must reach a lambda-literal argument/RHS even when
/// it is only known through the surrounding context rather than the callee's
/// own (possibly generic) signature:
///
/// - A generic collection factory's vararg element type
///   (`listOf<T>(vararg T): List<T>`) must be seeded from a declared
///   `List<(Int) -> Int>` result type before its lambda arguments are
///   inferred, or their implicit `it` parameter never resolves.
/// - A local/indexed reassignment (`x = { ... }`, `map[k] = { ... }`) must
///   pass the target's declared type into the RHS lambda, matching how a
///   `val`/`var` declaration's initializer already does.
/// - A lambda reassigned to a not-yet-initialized local (e.g. a recursive
///   `lateinit var` closure) may reference the target from inside its own
///   body; that read is deferred until the closure is later invoked, so it
///   must not trip a "must be initialized before use" diagnostic.
@Suite
struct LambdaExpectedTypeReassignmentTests {

    @Test func testDeclaredCollectionOfFunctionTypesSeedsLambdaItParameter() throws {
        let ctx = makeContextFromSources([
            """
            package sample0
            fun main() {
                val ops2: List<(Int) -> Int> = listOf({ it + 1 }, { it * 2 })
                println(ops2.map { it(10) })
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testRecursiveLambdaReassignedToInitializedVarSeesDeclaredType() throws {
        let ctx = makeContextFromSources([
            """
            package sample1
            fun main() {
                var fib: (Int) -> Int = { 0 }
                fib = { n -> if (n < 2) n else fib(n - 1) + fib(n - 2) }
                println(fib(10))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testLateinitSelfReferentialLambdaAssignmentTypeChecks() throws {
        let ctx = makeContextFromSources([
            """
            package sample2
            fun main() {
                lateinit var fact: (Int) -> Int
                fact = { if (it <= 1) 1 else it * fact(it - 1) }
                println(fact(5))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testIndexedMapAssignmentSeedsLambdaParameterTypes() throws {
        let ctx = makeContextFromSources([
            """
            package sample3
            fun main() {
                val fs = mutableMapOf<String, (Int) -> Int>()
                fs["inc"] = { it + 1 }
                val ops = mutableMapOf<String, (Int, Int) -> Int>()
                ops["-"] = { a, b -> a - b }
                println(fs.getValue("inc")(1))
                println(ops.getValue("-")(9, 4))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// Regression guard for a latent bug this fix's expected-type propagation
    /// exposed: an elvis expression's terminating RHS (`?: return null`) must
    /// keep being checked against the *enclosing function's* return type, not
    /// whatever expected type the surrounding reassignment happens to carry.
    @Test func testElvisReturnInsideReassignmentDoesNotMisuseAmbientExpectedType() throws {
        let ctx = makeContextFromSources([
            """
            package sample4
            fun parseTwoDigits(s: String): Int? = if (s.length == 2) 42 else null
            fun useElvisReturn(s: String): Int? {
                var value = 0
                value = parseTwoDigits(s) ?: return null
                return value
            }
            fun main() {
                println(useElvisReturn("42"))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// Same latent bug as the elvis case above, surfacing through `if`, `when`,
    /// and `try` instead: a branch that only exits via `return` must not be
    /// checked against the reassigned local's declared type.
    @Test func testIfBranchReturnInsideReassignmentDoesNotMisuseAmbientExpectedType() throws {
        let ctx = makeContextFromSources([
            """
            package sample5
            fun useIfReturn(c: Boolean): Int? {
                var value = 0
                value = if (c) 1 else return null
                return value
            }
            fun main() {
                println(useIfReturn(true))
                println(useIfReturn(false))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testWhenBranchReturnInsideReassignmentDoesNotMisuseAmbientExpectedType() throws {
        let ctx = makeContextFromSources([
            """
            package sample6
            fun useWhenReturn(c: Int): Int? {
                var value = 0
                value = when (c) {
                    1 -> 10
                    else -> return null
                }
                return value
            }
            fun main() {
                println(useWhenReturn(1))
                println(useWhenReturn(2))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTryCatchBranchReturnInsideReassignmentDoesNotMisuseAmbientExpectedType() throws {
        let ctx = makeContextFromSources([
            """
            package sample7
            fun useTryReturn(c: Boolean): Int? {
                var value = 0
                value = try {
                    if (c) throw RuntimeException() else 1
                } catch (e: Exception) {
                    return null
                }
                return value
            }
            fun main() {
                println(useTryReturn(false))
                println(useTryReturn(true))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
