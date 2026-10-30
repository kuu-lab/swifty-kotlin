#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LambdaLeadingEmptyStatementTests {
    @Test
    func leadingEmptyStatementPreservesLambdaValueAndPlainBlockValue() throws {
        let (ast, _) = try buildASTModule(from: """
        fun fromRun() = run { ; 7 }
        fun fromDirectInvocation() = { ; 42 }()
        fun fromIfBranch() = if (true) { ; 7 } else { 8 }
        """, includeStdlib: false)

        let lambdaValues = ast.arena.exprs.compactMap { expr -> Int? in
            guard case let .lambdaLiteral(_, body, _, _) = expr,
                  case let .blockExpr(statements, trailingExpr, _) = ast.arena.expr(body),
                  statements.isEmpty,
                  let trailingExpr,
                  case let .intLiteral(value, _) = ast.arena.expr(trailingExpr)
            else {
                return nil
            }
            return Int(value)
        }
        #expect(lambdaValues == [7, 42])

        let ifBranches = ast.arena.exprs.compactMap { expr -> (ExprID, ExprID?)? in
            guard case let .ifExpr(_, thenExpr, elseExpr, _) = expr else {
                return nil
            }
            return (thenExpr, elseExpr)
        }
        let (thenExpr, elseExpr) = try #require(ifBranches.first)
        guard case let .blockExpr(statements, trailingExpr, _) = ast.arena.expr(thenExpr),
              statements.isEmpty,
              let trailingExpr,
              case .intLiteral(7, _) = ast.arena.expr(trailingExpr),
              let elseExpr,
              case .blockExpr(_, let elseTrailing, _) = ast.arena.expr(elseExpr),
              let elseTrailing,
              case .intLiteral(8, _) = ast.arena.expr(elseTrailing)
        else {
            Issue.record("Expected both if branches to retain their trailing block expressions")
            return
        }
    }
}
#endif
