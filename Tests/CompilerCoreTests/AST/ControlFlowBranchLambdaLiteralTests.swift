#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ControlFlowBranchLambdaLiteralTests {
    private func bodyExpr(of name: String, in source: String) throws -> (ExprID, ASTModule) {
        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        let decl = try #require(firstFunDecl(named: name, in: ast, interner: ctx.interner))
        guard case let .expr(expr, _) = decl.body else {
            Issue.record("expected expression body")
            throw CancellationError()
        }
        return (expr, ast)
    }

    @Test
    func testIfBranchBracesWithArrowParseAsLambdaLiteral() throws {
        let (expr, ast) = try bodyExpr(of: "f", in: """
        fun f(flag: Boolean): (Int) -> Int = if (flag) { x -> x + 1 } else { x -> x - 1 }
        """)
        guard case let .ifExpr(_, thenExpr, elseExpr, _) = ast.arena.expr(expr) else {
            Issue.record("expected ifExpr")
            return
        }
        for branch in [thenExpr, try #require(elseExpr)] {
            guard case let .lambdaLiteral(params, _, _, _) = ast.arena.expr(branch) else {
                Issue.record("expected lambdaLiteral branch")
                continue
            }
            #expect(params.count == 1)
        }
    }

    @Test
    func testWhenBranchBracesWithArrowParseAsLambdaLiteral() throws {
        let (expr, ast) = try bodyExpr(of: "g", in: """
        fun g(flag: Boolean): (Int) -> Int = when (flag) { true -> { x -> x + 1 }; false -> { x -> x - 1 } }
        """)
        guard case let .whenExpr(_, branches, _, _) = ast.arena.expr(expr) else {
            Issue.record("expected whenExpr")
            return
        }
        #expect(branches.count == 2)
        for branch in branches {
            guard case .lambdaLiteral = ast.arena.expr(branch.body) else {
                Issue.record("expected lambdaLiteral branch body")
                continue
            }
        }
    }

    @Test
    func testPlainBlockBranchStaysBlock() throws {
        let (expr, ast) = try bodyExpr(of: "h", in: """
        fun h(flag: Boolean): Int = if (flag) { val a = 1; a + 1 } else { 0 }
        """)
        guard case let .ifExpr(_, thenExpr, _, _) = ast.arena.expr(expr) else {
            Issue.record("expected ifExpr")
            return
        }
        if case .lambdaLiteral = ast.arena.expr(thenExpr) {
            Issue.record("plain block must not become a lambda literal")
        }
    }
}
#endif
