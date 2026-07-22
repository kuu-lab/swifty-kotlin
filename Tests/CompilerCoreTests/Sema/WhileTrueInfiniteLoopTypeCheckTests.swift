#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-CAP-004: `while(true)` CAS loops / `Nothing`-typed infinite loops.
///
/// A `while(true)` (or `do { ... } while(true)`) loop with no `break` that
/// targets it never completes normally, so it types as `Nothing` rather than
/// `Unit` (matching Kotlin's control-flow rule). This lets a CAS retry loop
/// be a function's entire body — the shape `AtomicMigration.kt` deferred
/// (see its MIGRATION-ATOMIC-001 comment) and that blocked KSP-673.
@Suite
struct WhileTrueInfiniteLoopTypeCheckTests {

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostic assertions below validate the failure mode.
        }
        return ctx
    }

    // MARK: - Positive: CAS retry loop as a function's sole body statement

    @Test func testWhileTrueCasLoopSatisfiesNonUnitReturnType() throws {
        let source = """
        fun casLoop(cur: Int, next: Int): Int {
            while (true) {
                if (cur != next) return cur
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
        #expect(
            !(ctx.diagnostics.hasError),
            Comment(rawValue: "while(true) loop with no break should type as Nothing and satisfy Int: \(diagnostics)")
        )
    }

    // MARK: - Positive: do-while(true) is equally infinite

    @Test func testDoWhileTrueLoopSatisfiesNonUnitReturnType() throws {
        let source = """
        fun casLoop(cur: Int, next: Int): Int {
            do {
                if (cur != next) return cur
            } while (true)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
        #expect(
            !(ctx.diagnostics.hasError),
            Comment(rawValue: "do-while(true) loop with no break should type as Nothing and satisfy Int: \(diagnostics)")
        )
    }

    // MARK: - Positive: infinite loop satisfies a declared Nothing return type

    @Test func testWhileTrueLoopSatisfiesDeclaredNothingReturnType() throws {
        let source = """
        fun loopForever(): Nothing {
            var i = 0
            while (true) {
                i++
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
        #expect(
            !(ctx.diagnostics.hasError),
            Comment(rawValue: "while(true) with no break should satisfy a declared Nothing return type: \(diagnostics)")
        )
    }

    // MARK: - Positive: break@label targeting the loop itself is resolved

    //         correctly, so code after the loop stays reachable

    @Test func testLabeledBreakOnInfiniteLoopKeepsFollowingCodeReachable() throws {
        let source = """
        fun f(cond: Boolean): Int {
            loop@ while (true) {
                if (cond) break@loop
            }
            return 2
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics
        #expect(
            !(ctx.diagnostics.hasError),
            Comment(rawValue: "labeled while(true) with a break@label targeting it should type as Unit: \(diagnostics.map(\.message))")
        )
        assertNoDiagnostic("KSWIFTK-SEMA-0096", in: ctx)
    }

    // MARK: - Negative (soundness): a reachable break keeps the loop Unit-typed

    @Test func testWhileTrueLoopWithReachableBreakStaysUnitTyped() {
        let source = """
        fun f(): Int {
            while (true) {
                break
            }
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    // MARK: - Negative (soundness): only a literal `true` condition infers Nothing

    @Test func testWhileWithNonConstantConditionStaysUnitTyped() {
        let source = """
        fun f(x: Boolean): Int {
            while (x) {
                return 1
            }
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }
}
#endif
