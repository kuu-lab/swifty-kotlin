#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// kotlinc rejects an `if` without `else` wherever its value is consumed as an
/// expression (`INVALID_IF_AS_EXPRESSION`: "'if' must have both main and 'else'
/// branches when used as an expression"). Statement positions — including a
/// bare `if` as a lambda body's tail — keep treating the `if` as a statement;
/// a lambda whose tail is such an `if` still has to satisfy the expected
/// return type separately. Wrapping the `if` in parentheses forces expression
/// use and is rejected in every position (KUU-2982).
@Suite
struct IfExpressionElseRequiredTests {

    @Test func testIfExpressionRequiresElseSema() throws {
        let sources: [String] = [
            // 0: local initializer
            """
            package sample0
            fun f(c: Boolean) {
                val x = if (c) { }
            }

            """,

            // 1: an explicit Unit type does not make the initializer a
            // statement — the `if` is still used as an expression
            """
            package sample1
            fun f(c: Boolean) {
                val x: Unit = if (c) { }
            }

            """,

            // 2: expression-bodied function
            """
            package sample2
            fun f(c: Boolean) = if (c) { }

            """,

            // 3: return position
            """
            package sample3
            fun f(c: Boolean): Int {
                return if (c) { }
            }

            """,

            // 4: call argument, including when the parameter type is Unit
            """
            package sample4
            fun take(u: Unit) {}
            fun f(c: Boolean) {
                take(if (c) { })
                println(if (c) { })
            }

            """,

            // 5: elvis branch
            """
            package sample5
            fun f(c: Boolean, y: Int?) {
                val x = y ?: if (c) { }
            }

            """,

            // 6: parenthesized — the parens make it an expression even though
            // the wrapped value is discarded
            """
            package sample6
            fun f(c: Boolean) {
                val x = (if (c) { })
            }

            """,

            // 7: string template expression
            """
            package sample7
            fun f(c: Boolean) {
                val s = "${if (c) { }}"
            }

            """,

            // 8: cast operand
            """
            package sample8
            fun f(c: Boolean) {
                val x = if (c) { } as Unit
            }

            """,

            // 9: tail of a `try` block in expression position
            """
            package sample9
            fun f(c: Boolean) {
                val x = try { if (c) { } } catch (e: Exception) { }
            }

            """,

            // 10: `when` branch body of an expression `when`
            """
            package sample10
            fun f(c: Boolean, i: Int) {
                val x = when (i) { 1 -> if (c) { } else -> 2 }
            }

            """,

            // 11: nested tail of an expression `if` branch
            """
            package sample11
            fun f(a: Boolean, b: Boolean) {
                val x = if (a) { if (b) { } } else { 2 }
            }

            """,

            // 12: parenthesized tail of a lambda coerced to Unit — the parens
            // force expression use, so the `else` is still required
            """
            package sample12
            fun f(c: Boolean) {
                val g: () -> Unit = { (if (c) { }) }
            }

            """,

            // 13: parenthesized mid-statement — expression use again
            """
            package sample13
            fun f(c: Boolean) {
                (if (c) { })
            }

            """,

            // 14: control — a plain statement-position `if` without `else`
            """
            package sample14
            fun f(c: Boolean) {
                if (c) { }
            }

            """,

            // 15: control — `if`/`else` in expression position is legal
            """
            package sample15
            fun f(c: Boolean) {
                val x = if (c) { } else { }
                val y = if (c) 1 else 2
            }

            """,

            // 16: control — bare `if` as the tail of a lambda is a statement
            """
            package sample16
            fun f(c: Boolean) {
                val g = { if (c) { } }
                val h: () -> Unit = { if (c) { } }
                val i = { x: Int -> if (x > 0) { } }
            }

            """,

            // 17: control — `run`'s `() -> R` block keeps a bare tail `if`
            """
            package sample17
            fun f(c: Boolean) {
                run { if (c) { } }
                val x = run { if (c) { }; 5 }
            }

            """,

            // 18: control — `forEach` callback with a bare tail `if`
            """
            package sample18
            fun f() {
                listOf(1, 2).forEach { if (it > 0) { println(it) } }
            }

            """,

            // 19: control — statements inside named/anonymous function block
            // bodies are statements, not expressions
            """
            package sample19
            fun outer(c: Boolean) {
                fun inner() { if (c) { } }
            }
            fun main(c: Boolean) {
                val g = fun(): Int { if (c) { }; return 1 }
            }

            """,

            // 20: control — nested statement `if` inside statement `if`
            """
            package sample20
            fun f(a: Boolean, b: Boolean) {
                if (a) { if (b) { } }
                while (a) { if (b) { }; break }
            }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // 0-13: every else-less `if` consumed as an expression is rejected
            // with the dedicated diagnostic.
            for index in 0 ... 13 {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    diags.contains(where: { $0.code == "KSWIFTK-SEMA-0434" && $0.severity == .error }),
                    "else-less `if` used as an expression must be rejected (case \(index)): \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
            // 14-20: statement positions and bare lambda tails stay legal.
            for index in 14 ... 20 {
                let diags = diagnosticsForPath(paths[index], in: ctx)
                #expect(
                    !diags.contains(where: { $0.severity == .error }),
                    "case \(index) must compile without errors: \(diags.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }

    /// A `try` at a lambda tail is a statement position too: kotlinc does not
    /// push expression context into its branches even when the lambda is
    /// expected to return a value or the callee is unresolved, so an else-less
    /// `if` inside the try/catch bodies stays a statement (KUU-3163).
    @Test func testLambdaTailTryKeepsBranchesInStatementContextSema() throws {
        let sources: [String] = [
            // 0: resolved `() -> Unit` callee
            """
            package sample0
            fun take(block: () -> Unit) {}
            fun f(c: Boolean) {
                take {
                    try { if (c) { } } catch (e: Exception) { }
                }
            }

            """,

            // 1: unresolved callee — the lambda still checks without an
            // expected type, and the tail `try` must not flag the inner `if`
            """
            package sample1
            fun f(c: Boolean) {
                notAFunction {
                    try { if (c) { } } catch (e: Exception) { }
                }
            }

            """,

            // 2: `() -> Int` expected — the `try` value still feeds the return
            // type mismatch, but the inner `if` is not used as an expression
            """
            package sample2
            fun takeInt(block: () -> Int) {}
            fun f(c: Boolean) {
                takeInt {
                    try { if (c) { } } catch (e: Exception) { 1 }
                }
            }

            """,

            // 3: control — a try in expression position still requires `else`
            """
            package sample3
            fun f(c: Boolean) {
                val x = try { if (c) { } } catch (e: Exception) { }
            }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let statementTailDiags = diagnosticsForPath(paths[0], in: ctx)
            #expect(
                !statementTailDiags.contains(where: { $0.severity == .error }),
                "lambda tail `try` under a `() -> Unit` callee must compile clean: \(statementTailDiags.map { "\($0.code): \($0.message)" })"
            )

            let unresolvedCalleeDiags = diagnosticsForPath(paths[1], in: ctx)
            #expect(
                unresolvedCalleeDiags.contains(where: { $0.code == "KSWIFTK-SEMA-0023" && $0.severity == .error }),
                "the unresolved callee must still be reported: \(unresolvedCalleeDiags.map { "\($0.code): \($0.message)" })"
            )
            #expect(
                !unresolvedCalleeDiags.contains(where: { $0.code == "KSWIFTK-SEMA-0434" }),
                "the `if` inside the tail `try` is a statement: \(unresolvedCalleeDiags.map { "\($0.code): \($0.message)" })"
            )

            let intReturnDiags = diagnosticsForPath(paths[2], in: ctx)
            #expect(
                intReturnDiags.contains(where: { $0.severity == .error }),
                "a `() -> Int` lambda returning a Unit-valued `try` must be rejected: \(intReturnDiags.map { "\($0.code): \($0.message)" })"
            )
            #expect(
                !intReturnDiags.contains(where: { $0.code == "KSWIFTK-SEMA-0434" }),
                "kotlinc reports a return-type mismatch, not INVALID_IF_AS_EXPRESSION: \(intReturnDiags.map { "\($0.code): \($0.message)" })"
            )

            let expressionTryDiags = diagnosticsForPath(paths[3], in: ctx)
            #expect(
                expressionTryDiags.contains(where: { $0.code == "KSWIFTK-SEMA-0434" && $0.severity == .error }),
                "a `try` in expression position still requires `else` branches: \(expressionTryDiags.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    /// A bare `if` without `else` as a lambda tail is legal as a statement, but
    /// a non-Unit expected return type still reports a type mismatch — the
    /// same way kotlinc reports a return-type mismatch rather than
    /// INVALID_IF_AS_EXPRESSION.
    @Test func testLambdaTailIfStillChecksReturnTypeSema() throws {
        let sources: [String] = [
            """
            package sample0
            fun f(c: Boolean) {
                val g: () -> Int = { if (c) { } }
            }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let diags = diagnosticsForPath(paths[0], in: ctx)
            #expect(
                diags.contains(where: { $0.severity == .error }),
                "a `() -> Int` lambda returning an else-less `if` must be rejected: \(diags.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
#endif
