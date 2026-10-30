@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InfixCallLambdaImplicitLabelTests {
    @Test
    func infixCallStoresCalleeAsDirectLambdaLabel() throws {
        let (ast, ctx) = try buildASTModule(from: """
        infix fun Int.myMap(block: () -> Unit) {}
        fun test() {
            0 myMap { return@myMap }
        }
        """, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = function.body,
              let callID = statements.first,
              case let .memberCall(_, callee, _, args, _) = ast.arena.expr(callID),
              callee == ctx.interner.intern("myMap"),
              let argument = args.first,
              case let .lambdaLiteral(_, body, label?, _) = ast.arena.expr(argument.expr)
        else {
            Issue.record("Expected an infix call with a lambda labeled by its callee")
            return
        }

        #expect(label == ctx.interner.intern("myMap"))
        guard case let .returnExpr(_, returnLabel?, _) = ast.arena.expr(body) else {
            Issue.record("Expected the lambda body to retain its local return label")
            return
        }
        #expect(returnLabel == label)
    }

    @Test
    func infixCallKeepsFollowingInfixOperatorOutsideLambdaArgument() throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun test() = 0 first { 1 } second 2",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .expr(expression, _) = function.body,
              case let .memberCall(receiver, second, _, _, _) = ast.arena.expr(expression),
              second == ctx.interner.intern("second"),
              case let .memberCall(_, first, _, arguments, _) = ast.arena.expr(receiver),
              first == ctx.interner.intern("first"),
              let argument = arguments.first,
              case let .lambdaLiteral(_, _, label?, _) = ast.arena.expr(argument.expr)
        else {
            Issue.record("Expected left-associated infix calls with the lambda as the first call's argument")
            return
        }

        #expect(label == ctx.interner.intern("first"))
    }
}
