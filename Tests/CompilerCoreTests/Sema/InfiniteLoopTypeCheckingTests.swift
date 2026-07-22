#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-surface tests for `while(true)` / `do while(true)` infinite loops.
///
/// KSP-CAP-004: constant-true loops with no `break` targeting the loop are
/// typed as `Nothing`, so functions that return inside the loop (or that have
/// a `Nothing` return type) pass type checking.
@Suite
struct InfiniteLoopTypeCheckingTests {

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
    }

    @Test func testWhileTrueReturnLoopSatisfiesReturnType() {
        let ctx = runSemaCollectingDiagnostics("""
        fun f(cond: Boolean): Int {
            while (true) {
                if (cond) return 1
            }
        }
        """)
        #expect(
            !ctx.diagnostics.hasError,
            "while(true) with a return inside should satisfy an Int return type: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }

    @Test func testWhileTrueBreakLoopIsUnit() {
        let ctx = runSemaCollectingDiagnostics("""
        fun f(cond: Boolean) {
            while (true) {
                if (cond) break
            }
        }
        """)
        #expect(
            !ctx.diagnostics.hasError,
            "while(true) with a break inside should type as Unit: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }

    @Test func testNothingReturnInfiniteLoop() {
        let ctx = runSemaCollectingDiagnostics("""
        fun never(): Nothing {
            while (true) {}
        }
        """)
        #expect(
            !ctx.diagnostics.hasError,
            "while(true) {} should satisfy a Nothing return type: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }

    @Test func testDoWhileTrueReturnLoopSatisfiesReturnType() {
        let ctx = runSemaCollectingDiagnostics("""
        fun f(cond: Boolean): Int {
            do {
                if (cond) return 1
            } while (true)
        }
        """)
        #expect(
            !ctx.diagnostics.hasError,
            "do { ... } while(true) with a return inside should satisfy an Int return type: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }

    @Test func testLabeledWhileTrueBreakIsUnit() {
        let ctx = runSemaCollectingDiagnostics("""
        fun f(cond: Boolean) {
            loop@ while (true) {
                if (cond) break@loop
            }
        }
        """)
        #expect(
            !ctx.diagnostics.hasError,
            "labeled while(true) with a matching break should type as Unit: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }

    @Test func testNestedInnerBreakDoesNotReleaseOuterLoop() {
        let ctx = runSemaCollectingDiagnostics("""
        fun f(cond: Boolean): Int {
            outer@ while (true) {
                while (true) {
                    if (cond) break
                }
            }
        }
        """)
        #expect(
            !ctx.diagnostics.hasError,
            "inner while(true) break should not make the outer infinite loop Unit-typed: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }
}
#endif
