#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Block Expression Multi-Statement Evaluation Tests

// Covers: P5-47 — block expression with multiple statements + trailing expression
// Spec references: J6, J9, J11

@Suite
struct BlockExpressionTests {
    // Every case below must compile to KIR without errors. Since they share a
    // single pipeline run, per-case test functions would all fail identically
    // on any error — so assertions are grouped by what they check instead.
    private static let blockCaseSources: [String] = [
        // if-branch with multi-statement block (return pattern)
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
        // if-branch with multi-statement block and String trailing expr
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
        // when-branch with multi-statement block
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
        // try/catch with multi-statement block
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
        // empty block has Unit type
        """
        package blockcase4
        fun doNothing4(): Unit {
            if (true) {
            } else {
            }
        }
        fun main4() = doNothing4()
        """,
        // block with only declarations (no trailing expr -> Unit)
        """
        package blockcase5
        fun main5(): Unit {
            if (true) {
                val x = 42
                val y = 99
            }
        }
        """,
        // three val declarations and trailing expr
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
        // multi-statement block with var reassignment
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
        // if-branch with single val and trailing expr
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
        // try/catch both branches with multi-statement blocks
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
        // when expression-body with multi-statement branches
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

    private static nonisolated(unsafe) var _sharedBlockKIRCtx: CompilationContext?

    private func sharedBlockKIRCtx() throws -> CompilationContext {
        if let cached = Self._sharedBlockKIRCtx {
            return cached
        }
        let ctx = try makeSharedKIRContext(sources: Self.blockCaseSources)
        Self._sharedBlockKIRCtx = ctx
        return ctx
    }

    @Test
    func testBlockCaseSourcesCompileWithoutErrors() throws {
        let ctx = try sharedBlockKIRCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.code))")
    }

    @Test
    func testBlockCaseSourcesPopulateExprTypes() throws {
        let ctx = try sharedBlockKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
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

    // MARK: - Local function bodies must preserve semicolon splits inside nested blocks

    /// Compiles `source`, finds the top-level function `outerName`, and returns
    /// the body of the local function declared as its first statement.
    private func localFunBodyInOuterDecl(
        outerName: String,
        source: String
    ) throws -> (body: FunctionBody, ast: ASTModule, ctx: CompilationContext) {
        var extracted: (body: FunctionBody, ast: ASTModule, ctx: CompilationContext)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)

            let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
            let file = try #require(ast.files.first { $0.fileID == fileID })
            let outerDecl = try #require(file.topLevelDecls.compactMap { declID -> FunDecl? in
                guard case let .funDecl(fd) = ast.arena.decl(declID),
                      ctx.interner.resolve(fd.name) == outerName
                else {
                    return nil
                }
                return fd
            }.first)
            guard case let .block(outerStmts, _) = outerDecl.body else {
                Issue.record("Expected \(outerName) to have a block body")
                return
            }
            let outerFirstStmtID = try #require(outerStmts.first)
            guard case let .localFunDecl(_, _, _, innerBody, _, _) = try #require(ast.arena.expr(outerFirstStmtID)) else {
                Issue.record("Expected \(outerName)'s first statement to be a local fun declaration")
                return
            }
            extracted = (innerBody, ast, ctx)
        }
        return try #require(extracted)
    }

    private func localDeclName(_ exprID: ExprID, in ast: ASTModule, interner: StringInterner) -> String? {
        guard case let .localDecl(name, _, _, _, _, _) = ast.arena.expr(exprID) else {
            return nil
        }
        return interner.resolve(name)
    }

    @Test
    func testLocalFunctionNestedBlockPreservesInnerSemicolonSplit() throws {
        let (innerBody, ast, ctx) = try localFunBodyInOuterDecl(outerName: "outer", source: """
        fun outer() {
            fun inner() {
                if (true) { val a = 1; val b = 2 }
            }
        }
        fun main() = outer()
        """)

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
            stmts.compactMap { localDeclName($0, in: ast, interner: ctx.interner) } == ["a", "b"],
            "Nested block inside a local function's body should preserve both semicolon-separated statements"
        )
    }

    @Test
    func testLocalFunctionExpressionBodyPreservesInnerSemicolonSplit() throws {
        let (fBody, ast, ctx) = try localFunBodyInOuterDecl(outerName: "outer", source: """
        fun outer(): Int {
            fun f(): Int = if (true) { val a = 1; val b = 2; a + b } else 0
            return f()
        }
        fun main() = outer()
        """)

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
            stmts.compactMap { localDeclName($0, in: ast, interner: ctx.interner) } == ["a", "b"],
            "Nested block inside a local function's expression body should preserve both semicolon-separated statements"
        )
        #expect(trailing != nil, "Expected trailing `a + b` expression to survive")
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
