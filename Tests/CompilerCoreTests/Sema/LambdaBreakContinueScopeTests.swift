#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-surface tests for the control-flow scope of lambda bodies.
///
/// Non-local `break`/`continue` is legal only through inline parameters that
/// allow non-local control flow. Ordinary, `crossinline`, and `noinline`
/// lambda boundaries remain isolated from their enclosing loops.
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

            """,

            // 6: break through a normal inline parameter is legal
            """
            package sample6
            inline fun runInline(block: () -> Unit) { block() }
            fun g() {
                while (true) {
                    runInline { break }
                }
            }

            """,

            // 7: continue through a normal inline parameter is legal
            """
            package sample7
            inline fun runInline(block: () -> Unit) { block() }
            fun g() {
                var count = 0
                while (count < 2) {
                    runInline { count += 1; continue }
                }
            }

            """,

            // 8: a labeled break may target a loop across an inline lambda
            """
            package sample8
            inline fun runInline(block: () -> Unit) { block() }
            fun g() {
                outer@ while (true) {
                    runInline { break@outer }
                }
            }

            """,

            // 9: a labeled continue may target a loop across an inline lambda
            """
            package sample9
            inline fun runInline(block: () -> Unit) { block() }
            fun g() {
                var count = 0
                outer@ while (count < 2) {
                    runInline { count += 1; continue@outer }
                }
            }

            """,

            // 10: crossinline still rejects non-local break
            """
            package sample10
            inline fun runInline(crossinline block: () -> Unit) { block() }
            fun g() {
                while (true) {
                    runInline { break }
                }
            }

            """,

            // 11: noinline still rejects non-local continue
            """
            package sample11
            inline fun runInline(noinline block: () -> Unit) { block() }
            fun g() {
                while (true) {
                    runInline { continue }
                }
            }

            """,

            // 12: a labeled break through an anonymous function argument is legal
            """
            package sample12
            inline fun runInline(block: () -> Unit) { block() }
            fun g() {
                outer@ while (true) {
                    runInline(fun() { break@outer })
                }
            }

            """,

            // 13: a labeled continue through an anonymous function argument is legal
            """
            package sample13
            inline fun runInline(block: () -> Unit) { block() }
            fun g() {
                outer@ while (true) {
                    runInline(fun() { continue@outer })
                }
            }

            """,

            // 14: crossinline still rejects non-local break in an anonymous function
            """
            package sample14
            inline fun runInline(crossinline block: () -> Unit) { block() }
            fun g() {
                outer@ while (true) {
                    runInline(fun() { break@outer })
                }
            }

            """,

            // 15: a non-inline function does not permit a break to cross an anonymous function
            """
            package sample15
            fun run(block: () -> Unit) { block() }
            fun g() {
                outer@ while (true) {
                    run(fun() { break@outer })
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
            // 6-9: normal inline parameters admit non-local loop jumps.
            for index in 6 ... 9 {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    !diags.contains(where: { $0.severity == .error }),
                    "non-local loop jumps through an inline parameter must compile: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 10-11: crossinline/noinline parameters still reject non-local jumps.
            for (index, code) in [(10, "KSWIFTK-SEMA-0018"), (11, "KSWIFTK-SEMA-0019")] {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    diags.contains(where: { $0.code == code && $0.severity == .error }),
                    "non-local jump through a restricted inline parameter must be rejected: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 12-13: inline anonymous functions admit labeled non-local loop jumps.
            for index in 12 ... 13 {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    !diags.contains(where: { $0.severity == .error }),
                    "non-local loop jumps through an inline anonymous function must compile: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 14-15: restricted or non-inline anonymous function arguments reject the jump.
            for index in 14 ... 15 {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    diags.contains(where: { $0.code == "KSWIFTK-SEMA-0018" && $0.severity == .error }),
                    "a non-local jump through a restricted anonymous function must be rejected: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
#endif
