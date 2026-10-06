#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-1380: a lambda literal is a `primaryExpression`, so it takes the same
/// `postfixUnarySuffix` chain as any other primary — `{ ... }()` invokes the
/// literal directly. In call-argument position the `{` shortcut used to return
/// the lambda without continuing the postfix chain, so `println({ 42 }())`
/// failed with `KSWIFTK-PARSE-0015`; the infix chain (`{ 5 }() + { 6 }()`)
/// stopped at the same place.
@Suite
struct LambdaLiteralDirectInvocationTests {
    private func mainStatements(in source: String) throws -> ([ExprID], ASTModule) {
        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let decl = try #require(firstFunDecl(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = decl.body else {
            Issue.record("expected block body")
            throw CancellationError()
        }
        return (statements, ast)
    }

    private func callArgExpr(of statement: ExprID, in ast: ASTModule) throws -> ExprID {
        guard case let .call(_, _, args, _) = ast.arena.expr(statement),
              let arg = args.first?.expr
        else {
            Issue.record("expected a call statement with an argument")
            throw CancellationError()
        }
        return arg
    }

    @Test
    func testBareLambdaArgumentContinuesIntoCall() throws {
        let (statements, ast) = try mainStatements(in: """
        fun main() {
            println({ 42 }())
        }
        """)
        let arg = try callArgExpr(of: try #require(statements.first), in: ast)
        guard case let .call(callee, _, _, _) = ast.arena.expr(arg) else {
            Issue.record("expected the argument to be a call")
            return
        }
        guard case .lambdaLiteral = ast.arena.expr(callee) else {
            Issue.record("expected the call callee to be a lambda literal")
            return
        }
    }

    @Test
    func testParenthesizedLambdaArgumentContinuesIntoCall() throws {
        let (statements, ast) = try mainStatements(in: """
        fun main() {
            println(({ 42 })())
        }
        """)
        let arg = try callArgExpr(of: try #require(statements.first), in: ast)
        guard case let .call(callee, _, _, _) = ast.arena.expr(arg) else {
            Issue.record("expected the argument to be a call")
            return
        }
        guard case .lambdaLiteral = ast.arena.expr(callee) else {
            Issue.record("expected the call callee to be a lambda literal")
            return
        }
    }

    @Test
    func testParenthesizedLambdaArgumentStaysLambdaWithoutSuffix() throws {
        let (statements, ast) = try mainStatements(in: """
        fun main() {
            println(({ 42 }))
        }
        """)
        let arg = try callArgExpr(of: try #require(statements.first), in: ast)
        guard case .lambdaLiteral = ast.arena.expr(arg) else {
            Issue.record("expected the argument to stay a lambda literal")
            return
        }
    }

    @Test
    func testLambdaCallArgumentContinuesIntoBinaryExpression() throws {
        let (statements, ast) = try mainStatements(in: """
        fun main() {
            println({ 5 }() + { 6 }())
        }
        """)
        let arg = try callArgExpr(of: try #require(statements.first), in: ast)
        guard case let .binary(_, lhs, rhs, _) = ast.arena.expr(arg) else {
            Issue.record("expected the argument to be a binary expression")
            return
        }
        for side in [lhs, rhs] {
            guard case let .call(callee, _, _, _) = ast.arena.expr(side),
                  case .lambdaLiteral = ast.arena.expr(callee)
            else {
                Issue.record("expected each binary operand to invoke a lambda literal")
                return
            }
        }
    }

    @Test
    func testFollowingArgumentsStillParse() throws {
        let (statements, ast) = try mainStatements(in: """
        fun main() {
            foo({ 42 }(), 2, { 7 })
        }
        """)
        guard case let .call(_, _, args, _) = ast.arena.expr(try #require(statements.first)) else {
            Issue.record("expected a call statement")
            return
        }
        #expect(args.count == 3)
        guard case let .call(callee, _, _, _) = ast.arena.expr(try #require(args.first).expr),
              case .lambdaLiteral = ast.arena.expr(callee)
        else {
            Issue.record("expected the first argument to invoke a lambda literal")
            return
        }
    }
}
#endif
