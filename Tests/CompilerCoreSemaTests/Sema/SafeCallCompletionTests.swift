#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3099: a `?.` short-circuits the rest of its postfix chain, so the
/// value/index arguments of `a?.b = v` and `a?.b[i] = v` may never run. The
/// statement can still complete normally (null receiver path), which means a
/// non-Unit function ending in such an assignment must report a missing
/// return — matching kotlinc.
@Suite
struct SafeCallCompletionTests {
    @Test func testSafeAssignmentWithNonCompletingValueStillReportsMissingReturn() throws {
        let sources = [
            // `b?.n = return 1` — the reported repro.
            "class Box(var n: Int)\nfun f(b: Box?): Int { b?.n = return 1 }",
            // Same bug with a `throw` RHS.
            "class Box(var n: Int)\nfun f(b: Box?): Int { b?.n = throw IllegalStateException() }",
            // Same bug with a Nothing-returning RHS call.
            "fun fail(): Nothing = throw IllegalStateException()\nclass Box(var n: Int)\nfun f(b: Box?): Int { b?.n = fail() }",
            // Nested `?.` chain.
            "class Box(var n: Int) { val inner: Box get() = this }\nfun f(b: Box?): Int { b?.inner?.n = return 1 }",
            // `?.` guards the index *and* the value of an indexed assignment.
            "class Box(val arr: IntArray)\nfun f(b: Box?): Int { b?.arr[0] = return 1 }",
            // Multi-index chain stays inside the same safe navigation.
            "class Box(val arr: Array<IntArray>)\nfun f(b: Box?): Int { b?.arr[0][1] = return 1 }",
            // Guarded indexed read.
            "class Box(val arr: IntArray)\nfun f(b: Box?): Int { b?.arr[return 1] }",
            // kotlinc keeps the conservative verdict even when the receiver
            // can provably not be null.
            "class Box(var n: Int)\nfun f(b: Box): Int { b?.n = return 1 }",
            "class Box(var n: Int)\nfun f(c: Box?): Int { (c ?: return 2)?.n = return 1 }",
        ]
        let ctx = makeContextFromSources(sources.enumerated().map { index, source in
            "package sample\(index)\n\(source)"
        })
        try runSema(ctx)
        for index in sources.indices {
            let diagnostics = diagnosticsForPath(ctx.options.inputs[index], in: ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0469", in: diagnostics)
        }
    }

    @Test func testNonGuardedAssignmentsKeepRequiringCompletion() throws {
        // `!!` breaks the `?.` guard: the null path fails at the `!!` instead
        // of skipping the tail, so the function can never complete normally
        // and no missing return is reported — kotlinc accepts these.
        let acceptedSources = [
            "class Box(val arr: IntArray)\nfun f(b: Box?): Int { b?.arr!![0] = return 1 }",
            "class Box(var n: Int)\nfun f(b: Box?): Int { b!!.n = return 1 }",
            // Guarded assignment inside a conditional branch followed by a
            // real return is fine.
            "class Box(var n: Int)\nfun f(b: Box?, flag: Boolean): Int { if (flag) { b?.n = return 1 }; return 2 }",
            // Plain safe assignment plus explicit return stays accepted.
            "class Box(var n: Int)\nfun f(b: Box?): Int { b?.n = 5; return 0 }",
        ]
        let ctx = makeContextFromSources(acceptedSources.enumerated().map { index, source in
            "package sample\(index)\n\(source)"
        })
        try runSema(ctx)
        for index in acceptedSources.indices {
            let diagnostics = diagnosticsForPath(ctx.options.inputs[index], in: ctx)
            #expect(!diagnostics.hasError, "got: \(diagnostics)")
        }
    }
}
#endif
