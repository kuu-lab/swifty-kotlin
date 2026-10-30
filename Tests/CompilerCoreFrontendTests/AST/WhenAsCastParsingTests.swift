#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct WhenAsCastParsingTests {
    @Test
    func parsesDirectWhenExpressionAsTailCast() throws {
        let lexed = lex("when (x) { is Int -> x; else -> x } as T")
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )

        let expression = try #require(parser.parse())
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        guard case let .asCast(operand, _, _, _) = arena.expr(expression),
              case .whenExpr = arena.expr(operand)
        else {
            Issue.record("Expected the direct expression to cast the complete when expression")
            return
        }
    }

    @Test(arguments: ["as", "as?"], [" ", "\n    "])
    func castsTheCompleteWhenExpressionAtFunctionBodyTail(
        castOperator: String,
        separator: String
    ) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun <T> f(x: T): T = when (x) { is Int -> x; else -> x }\(separator)\(castOperator) T",
            includeStdlib: false
        )

        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let function = try #require(firstFunDecl(named: "f", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body,
              case let .asCast(operand, _, isSafe, _) = ast.arena.expr(body),
              case let .whenExpr(_, branches, elseExpr, _) = ast.arena.expr(operand)
        else {
            Issue.record("Expected the function body to cast the complete when expression")
            return
        }
        #expect(isSafe == (castOperator == "as?"))
        #expect(branches.count == 1)
        #expect(elseExpr != nil)
    }
}
#endif
