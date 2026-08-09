#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Block Expression Multi-Statement Evaluation Tests

// Covers: P5-47 — block expression with multiple statements + trailing expression
// Spec references: J6, J9, J11

@Suite
struct BlockExpressionTests {

    @Test
    func testBlockExpressionsKIR() throws {
        let sources: [String] = [
            // 0: single expression block always produces blockExpr
            """
            fun main0(): Int {
                return if (true) { 42 } else { 0 }
            }
            """,
            // 1: if branch with multi-statement block return pattern
            """
            fun compute1(): Int {
                return if (true) {
                    val a = 10
                    val b = 20
                    a + b
                } else {
                    0
                }
            }
            fun main1() = compute1()
            """,
            // 2: if branch with multi-statement block and String trailing expr
            """
            fun greet2(): String {
                return if (true) {
                    val x = 42
                    "hello"
                } else {
                    "world"
                }
            }
            fun main2() = greet2()
            """,
            // 3: when branch with multi-statement block
            """
            fun classify3(x: Int): Int {
                return when (x) {
                    1 -> {
                        val a = 10
                        a + 1
                    }
                    else -> {
                        val b = 99
                        b
                    }
                }
            }
            fun main3() = classify3(1)
            """,
            // 4: try/catch with multi-statement block
            """
            fun compute4(): Int {
                return try {
                    val x = 1
                    val y = 2
                    x + y
                } catch (e: Exception) {
                    0
                }
            }
            fun main4() = compute4()
            """,
            // 5: empty block has Unit type
            """
            fun doNothing5(): Unit {
                if (true) {
                } else {
                }
            }
            fun main5() = doNothing5()
            """,
            // 6: block expression with only declarations (no trailing expr -> Unit)
            """
            fun main6(): Unit {
                if (true) {
                    val x = 42
                    val y = 99
                }
            }
            """,
            // 7: multi-statement block with three val declarations and trailing expr
            """
            fun compute7(): Int {
                return if (true) {
                    val a = 1
                    val b = 2
                    val c = 3
                    a + b + c
                } else {
                    0
                }
            }
            fun main7() = compute7()
            """,
            // 8: multi-statement block with var reassignment
            """
            fun compute8(): Int {
                return if (true) {
                    var x = 10
                    x = x + 5
                    x
                } else {
                    0
                }
            }
            fun main8() = compute8()
            """,
            // 9: if branch with single val and trailing expr
            """
            fun compute9(): Int {
                return if (true) {
                    val x = 42
                    x
                } else {
                    0
                }
            }
            fun main9() = compute9()
            """,
            // 10: try/catch both branches with multi-statement blocks
            """
            fun compute10(): Int {
                return try {
                    val a = 10
                    val b = 20
                    a + b
                } catch (e: Exception) {
                    val fallback = -1
                    fallback
                }
            }
            fun main10() = compute10()
            """,
            // 11: when expression-body with multi-statement branches
            """
            fun classify11(x: Int): Int = when (x) {
                1 -> {
                    val base = 100
                    base + x
                }
                2 -> {
                    val multiplier = 10
                    multiplier * x
                }
                else -> {
                    val fallback = -1
                    fallback
                }
            }
            fun main11() = classify11(2)
            """,
            // 12: AST structure — blockExpr with statements and trailing expression
            """
            fun computeAST(): Int {
                return if (true) {
                    val a = 10
                    a + 1
                } else {
                    0
                }
            }
            fun mainAST() = computeAST()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            #expect(!(sema.bindings.exprTypes.isEmpty))

            let ast = try #require(ctx.ast)

            var foundBlockExpr = false
            var foundMultiStmtBlock = false
            for expr in ast.arena.exprs {
                if case .blockExpr = expr {
                    foundBlockExpr = true
                }
                if case let .blockExpr(stmts, trailing, _) = expr,
                   !stmts.isEmpty, trailing != nil
                {
                    foundMultiStmtBlock = true
                }
            }
            #expect(foundBlockExpr, "Expected at least one blockExpr in AST")
            #expect(foundMultiStmtBlock, "Expected a blockExpr with statements and trailing expression")

            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
            }
        }
    }
}
#endif
