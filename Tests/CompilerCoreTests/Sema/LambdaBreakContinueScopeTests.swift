#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-surface tests for the control-flow scope of lambda bodies.
///
/// BUG-253: non-local `break`/`continue` (stable since Kotlin 2.2) is not
/// implemented in Lowering, so a jump that has to leave the lambda is silently
/// dropped — the enclosing loop keeps running. `enteringLambdaBody()` resets
/// the loop stacks so such a jump is rejected by `KSWIFTK-SEMA-0018` /
/// `KSWIFTK-SEMA-0019` instead of miscompiling. A loop *inside* the lambda
/// re-enters loop scope and must keep compiling.
@Suite
struct LambdaBreakContinueScopeTests {

    @Test func testLambdaBreakContinueScopeSema() throws {
        let sources: [String] = [
            // 0: break crossing the lambda boundary is rejected
            """
            package sample0
            fun run0(f: () -> Unit) { f() }
            fun g(cond: Boolean) {
                while (cond) {
                    run0 { break }
                }
            }

            """,

            // 1: continue crossing the lambda boundary is rejected
            """
            package sample1
            fun run0(f: () -> Unit) { f() }
            fun g(cond: Boolean) {
                while (cond) {
                    run0 { continue }
                }
            }

            """,

            // 2: a labeled break naming an enclosing loop is rejected too
            """
            package sample2
            fun run0(f: () -> Unit) { f() }
            fun g(cond: Boolean) {
                outer@ while (cond) {
                    run0 { break@outer }
                }
            }

            """,

            // 3: a loop inside the lambda re-enters loop scope
            """
            package sample3
            fun run0(f: () -> Unit) { f() }
            fun g(cond: Boolean) {
                run0 {
                    while (true) {
                        if (cond) break
                    }
                }
            }

            """,

            // 4: control — break in a plain loop body is unaffected
            """
            package sample4
            fun g(cond: Boolean) {
                while (cond) {
                    if (cond) break
                }
            }

            """,

            // 5: the lambda's own loop swallows the break; the outer loop is
            // not involved, so this stays legal
            """
            package sample5
            fun run0(f: () -> Unit) { f() }
            fun g(cond: Boolean) {
                while (cond) {
                    run0 {
                        while (cond) {
                            if (cond) break
                        }
                    }
                }
            }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // 0: break crossing the lambda boundary
            do {
                let diags = diagnosticsForPath(paths[0], in: ctx)
                #expect(
                    diags.contains(where: { $0.code == "KSWIFTK-SEMA-0018" && $0.severity == .error }),
                    "break inside a lambda must not silently target the enclosing loop: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 1: continue crossing the lambda boundary
            do {
                let diags = diagnosticsForPath(paths[1], in: ctx)
                #expect(
                    diags.contains(where: { $0.code == "KSWIFTK-SEMA-0019" && $0.severity == .error }),
                    "continue inside a lambda must not silently target the enclosing loop: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 2: labeled break crossing the lambda boundary
            do {
                let diags = diagnosticsForPath(paths[2], in: ctx)
                #expect(
                    diags.contains(where: { $0.severity == .error }),
                    "break@label inside a lambda must be rejected: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 3: loop inside the lambda
            do {
                let diags = diagnosticsForPath(paths[3], in: ctx)
                #expect(
                    !diags.contains(where: { $0.severity == .error }),
                    "a loop inside the lambda re-enters loop scope: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 4: control
            do {
                let diags = diagnosticsForPath(paths[4], in: ctx)
                #expect(
                    !diags.contains(where: { $0.severity == .error }),
                    "break in a plain loop body must stay legal: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 5: nested loop inside a lambda inside a loop
            do {
                let diags = diagnosticsForPath(paths[5], in: ctx)
                #expect(
                    !diags.contains(where: { $0.severity == .error }),
                    "the lambda's own loop must absorb the break: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
#endif
