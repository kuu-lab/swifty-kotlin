#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// kotlinc rejects a `return` bound to a function or accessor declared with
/// an `= expression` body **without** an explicit return type
/// (`fun f() = return`), including `return` nested in `if`/`when`/`try`
/// branches — `return` is not an expression, unlike `throw`. With a declared
/// return type the same `return` is legal and merely type-checked. A
/// `return` that crosses an inline-lambda boundary to reach the
/// expression-body function only warns under kotlinc (KTLC-288), so it stays
/// accepted here as well (KUU-2989).
@Suite
struct ReturnInExpressionBodyTests {

    @Test func testReturnInExpressionBodySema() throws {
        let sources: [String] = [
            // 0: bare return as the whole expression body
            """
            package sample0
            fun f() = return

            """,

            // 1: return nested in an `if` branch of the expression body
            """
            package sample1
            fun f(c: Boolean) = if (c) return else 0

            """,

            // 2: return nested in a `try` block of the expression body
            """
            package sample2
            fun f() = try { return } finally {}

            """,

            // 3: a labeled return naming the function itself
            """
            package sample3
            fun f() = return@f

            """,

            // 4: an expression-bodied getter without declared property type
            """
            package sample4
            val g
                get() = return

            """,

            // 5: an expression-bodied local function
            """
            package sample5
            fun outer() {
                fun g() = return
            }

            """,

            // 6: control — an explicit return type makes `return` legal
            """
            package sample6
            fun f(): Unit = return
            fun g(): Int = return 1
            fun h(c: Boolean): Unit = if (c) return else Unit
            fun i(): Unit = try { return } finally {}

            """,

            // 7: control — kotlinc only warns for a non-local return that
            // crosses an inline lambda (KTLC-288), so it stays accepted
            """
            package sample7
            inline fun runInline(block: () -> Unit) { block() }
            fun f() = runInline { return }

            """,

            // 8: control — a lambda-labeled return targets the lambda, not f
            """
            package sample8
            inline fun runInline(block: () -> Unit) { block() }
            fun f() = runInline { return@runInline }

            """,

            // 9: control — an explicit property type leaves the getter legal
            """
            package sample9
            val g: Unit
                get() = return

            """,

            // 10: control — block bodies keep plain and labeled returns legal
            """
            package sample10
            fun f() {
                return@f
            }
            fun g() {
                return
            }

            """,

            // 11: control — a non-local return in a block body stays legal
            """
            package sample11
            inline fun runInline(block: () -> Unit) { block() }
            fun f() {
                runInline { return }
            }

            """,

            // 12: control — a block-bodied member re-derives the flag
            """
            package sample12
            fun f() = object {
                fun m() { return }
            }

            """,

            // 13: control — `throw` is a real expression and stays legal
            """
            package sample13
            fun f(): Nothing = throw Exception("boom")

            """,

            // 14: control — a local function with an explicit return type
            """
            package sample14
            fun outer() {
                fun g(): Unit = return
            }

            """,

            // 15: break was already rejected outside loops (SEMA-0018)
            """
            package sample15
            fun f() = break

            """,

            // 16: continue was already rejected outside loops (SEMA-0019)
            """
            package sample16
            fun f() = continue

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // 0-5: every `return` prohibited in an expression body without a
            // declared return type is rejected with the dedicated diagnostic.
            for index in 0 ... 5 {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    diags.contains(where: { $0.code == "KSWIFTK-SEMA-0311" && $0.severity == .error }),
                    "return prohibited in an implicit-typed expression body must be rejected (case \(index)): \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 6-14: declared return types, lambda-labeled/non-local returns,
            // block bodies, nested functions, and `throw` stay legal.
            for index in 6 ... 14 {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    !diags.contains(where: { $0.severity == .error }),
                    "case \(index) must compile without errors: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 15-16: break/continue keep their pre-existing loop diagnostics.
            for (index, code) in [(15, "KSWIFTK-SEMA-0018"), (16, "KSWIFTK-SEMA-0019")] {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    diags.contains(where: { $0.code == code && $0.severity == .error }),
                    "case \(index) must be rejected with \(code): \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
#endif
