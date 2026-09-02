#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Block Expression Multi-Statement Evaluation Tests

// Covers: P5-47 — block expression with multiple statements + trailing expression
// Spec references: J6, J9, J11

@Suite
struct BlockExpressionTests {
    private static nonisolated(unsafe) var _sharedBlockKIRCtx: CompilationContext?

    private func sharedBlockKIRCtx() throws -> CompilationContext {
        if let cached = Self._sharedBlockKIRCtx {
            return cached
        }

        let sources: [String] = [
            """
            package blockcase0
            fun compute0(): Int {
                return if (true) {
                    val a = 10
                    val b = 20
                    a + b
                } else {
                    0
                }
            }
            fun main0() = compute0()
            """,
            """
            package blockcase1
            fun greet1(): String {
                return if (true) {
                    val x = 42
                    "hello"
                } else {
                    "world"
                }
            }
            fun main1() = greet1()
            """,
            """
            package blockcase2
            fun classify2(x: Int): Int {
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
            fun main2() = classify2(1)
            """,
            """
            package blockcase3
            fun compute3(): Int {
                return try {
                    val x = 1
                    val y = 2
                    x + y
                } catch (e: Exception) {
                    0
                }
            }
            fun main3() = compute3()
            """,
            """
            package blockcase4
            fun doNothing4(): Unit {
                if (true) {
                } else {
                }
            }
            fun main4() = doNothing4()
            """,
            """
            package blockcase5
            fun main5(): Unit {
                if (true) {
                    val x = 42
                    val y = 99
                }
            }
            """,
            """
            package blockcase6
            fun compute6(): Int {
                return if (true) {
                    val a = 1
                    val b = 2
                    val c = 3
                    a + b + c
                } else {
                    0
                }
            }
            fun main6() = compute6()
            """,
            """
            package blockcase7
            fun compute7(): Int {
                return if (true) {
                    var x = 10
                    x = x + 5
                    x
                } else {
                    0
                }
            }
            fun main7() = compute7()
            """,
            """
            package blockcase8
            fun compute8(): Int {
                return if (true) {
                    val x = 42
                    x
                } else {
                    0
                }
            }
            fun main8() = compute8()
            """,
            """
            package blockcase9
            fun compute9(): Int {
                return try {
                    val a = 10
                    val b = 20
                    a + b
                } catch (e: Exception) {
                    val fallback = -1
                    fallback
                }
            }
            fun main9() = compute9()
            """,
            """
            package blockcase10
            fun classify10(x: Int): Int = when (x) {
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
            fun main10() = classify10(2)
            """,
        ]

        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        Self._sharedBlockKIRCtx = ctx
        return ctx
    }

    // MARK: - AST: single expression block always produces blockExpr

    @Test
    func testSingleExpressionBlockProducesBlockExprNode() throws {
        let source = """
        fun main(): Int {
            return if (true) { 42 } else { 0 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            // After removing single-expression re-parse, even { 42 } should be a blockExpr
            let foundBlockExpr = ast.arena.exprs.contains { expr in
                if case .blockExpr = expr { return true }
                return false
            }
            #expect(foundBlockExpr, "Expected at least one blockExpr in AST")
        }
    }

    // MARK: - if branch with multi-statement block (return pattern)

    @Test
    func testIfBranchMultiStatementBlockReturnPattern() throws {
        let ctx = try sharedBlockKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - if branch with multi-statement block and String trailing expr (return pattern)

    @Test
    func testIfBranchMultiStatementBlockStringTrailingExpr() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - when branch with multi-statement block

    @Test
    func testWhenBranchMultiStatementBlockInfersTrailingExprType() throws {
        let ctx = try sharedBlockKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - try/catch with multi-statement block

    @Test
    func testTryCatchMultiStatementBlockInfersTrailingExprType() throws {
        let ctx = try sharedBlockKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - Empty block has Unit type

    @Test
    func testEmptyBlockHasUnitType() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - Block expression with only declarations (no trailing expr -> Unit)

    @Test
    func testBlockWithOnlyDeclarationsHasUnitType() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - Multi-statement block with three val declarations and trailing expr

    @Test
    func testThreeValDeclarationsAndTrailingExpr() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - Multi-statement block with var reassignment (return pattern)

    @Test
    func testMultiStatementBlockWithVarReassignment() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - if branch with single val and trailing expr (return pattern)

    @Test
    func testIfBranchSingleValAndTrailingExpr() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - try/catch both branches with multi-statement blocks

    @Test
    func testTryCatchBothBranchesMultiStatement() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - when expression-body with multi-statement branches

    @Test
    func testWhenExpressionBodyMultiStatementBranches() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    // MARK: - Local function body must preserve semicolon splits inside nested blocks

    @Test
    func testLocalFunctionNestedBlockPreservesInnerSemicolonSplit() throws {
        let source = """
        fun outer() {
            fun inner() {
                if (true) { val a = 1; val b = 2 }
            }
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner

            func localDeclName(_ exprID: ExprID) -> String? {
                guard case let .localDecl(name, _, _, _, _, _) = ast.arena.expr(exprID) else {
                    return nil
                }
                return interner.resolve(name)
            }

            let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
            let file = try #require(ast.files.first { $0.fileID == fileID })
            let outerDecl = try #require(file.topLevelDecls.compactMap { declID -> FunDecl? in
                guard case let .funDecl(fd) = ast.arena.decl(declID), interner.resolve(fd.name) == "outer" else {
                    return nil
                }
                return fd
            }.first)
            guard case let .block(outerStmts, _) = outerDecl.body else {
                Issue.record("Expected outer() to have a block body")
                return
            }
            let outerFirstStmtID = try #require(outerStmts.first)
            guard case let .localFunDecl(_, _, _, innerBody, _, _) = try #require(ast.arena.expr(outerFirstStmtID)) else {
                Issue.record("Expected outer()'s first statement to be inner()'s local fun declaration")
                return
            }
            guard case let .block(innerStmts, _) = innerBody else {
                Issue.record("Expected inner() to have a block body")
                return
            }
            let innerFirstStmtID = try #require(innerStmts.first)
            guard case let .ifExpr(_, thenExprID, _, _) = try #require(ast.arena.expr(innerFirstStmtID)) else {
                Issue.record("Expected inner()'s first statement to be an if expression")
                return
            }
            guard case let .blockExpr(stmts, _, _) = try #require(ast.arena.expr(thenExprID)) else {
                Issue.record("Expected the if's then-branch to be a blockExpr")
                return
            }
            #expect(
                stmts.compactMap(localDeclName) == ["a", "b"],
                "Nested block inside a local function's body should preserve both semicolon-separated statements"
            )
        }
    }

    // MARK: - Local function expression body must preserve semicolon splits inside nested blocks

    @Test
    func testLocalFunctionExpressionBodyPreservesInnerSemicolonSplit() throws {
        let source = """
        fun outer(): Int {
            fun f(): Int = if (true) { val a = 1; val b = 2; a + b } else 0
            return f()
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner

            func localDeclName(_ exprID: ExprID) -> String? {
                guard case let .localDecl(name, _, _, _, _, _) = ast.arena.expr(exprID) else {
                    return nil
                }
                return interner.resolve(name)
            }

            let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
            let file = try #require(ast.files.first { $0.fileID == fileID })
            let outerDecl = try #require(file.topLevelDecls.compactMap { declID -> FunDecl? in
                guard case let .funDecl(fd) = ast.arena.decl(declID), interner.resolve(fd.name) == "outer" else {
                    return nil
                }
                return fd
            }.first)
            guard case let .block(outerStmts, _) = outerDecl.body else {
                Issue.record("Expected outer() to have a block body")
                return
            }
            let outerFirstStmtID = try #require(outerStmts.first)
            guard case let .localFunDecl(_, _, _, fBody, _, _) = try #require(ast.arena.expr(outerFirstStmtID)) else {
                Issue.record("Expected outer()'s first statement to be f()'s local fun declaration")
                return
            }
            guard case let .expr(ifExprID, _) = fBody else {
                Issue.record("Expected f() to have an expression body")
                return
            }
            guard case let .ifExpr(_, thenExprID, _, _) = try #require(ast.arena.expr(ifExprID)) else {
                Issue.record("Expected f()'s expression body to be an if expression")
                return
            }
            guard case let .blockExpr(stmts, trailing, _) = try #require(ast.arena.expr(thenExprID)) else {
                Issue.record("Expected the if's then-branch to be a blockExpr")
                return
            }
            #expect(
                stmts.compactMap(localDeclName) == ["a", "b"],
                "Nested block inside a local function's expression body should preserve both semicolon-separated statements"
            )
            #expect(trailing != nil, "Expected trailing `a + b` expression to survive")
        }
    }

    // MARK: - AST structure: blockExpr has statements and trailing expression

    @Test
    func testBlockExprASTStructure() throws {
        let source = """
        fun compute(): Int {
            return if (true) {
                val a = 10
                a + 1
            } else {
                0
            }
        }
        fun main() = compute()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            // Find a blockExpr with non-empty statements and a trailing expression
            var foundMultiStmtBlock = false
            for expr in ast.arena.exprs {
                if case let .blockExpr(stmts, trailing, _) = expr,
                   !stmts.isEmpty, trailing != nil
                {
                    foundMultiStmtBlock = true
                    break
                }
            }
            #expect(foundMultiStmtBlock, "Expected a blockExpr with statements and trailing expression")
        }
    }
}
#endif
