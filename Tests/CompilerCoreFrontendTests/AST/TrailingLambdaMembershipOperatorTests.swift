@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct TrailingLambdaMembershipOperatorTests {
    @Test(arguments: [
        ("c.let { it.toInt() } in x", false),
        ("c.let { it.toInt() } !in x", true),
        ("c?.let { it.toInt() } in x", false),
        ("c?.let { it.toInt() } !in x", true),
        ("(c.let { it.toInt() }) in x", false),
        ("(c.let { it.toInt() }) !in x", true),
    ])
    func membershipOperatorContinuesPastTrailingLambda(expression: String, negated: Bool) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun test(c: String?, x: Set<Int>) = \(expression)
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .expr(bodyExpression, _) = function.body else {
            Issue.record("Expected an expression-bodied function")
            return
        }

        let lhs: ExprID
        let rhs: ExprID
        switch (negated, ast.arena.expr(bodyExpression)) {
        case let (false, .inExpr(parsedLHS, parsedRHS, _)):
            lhs = parsedLHS
            rhs = parsedRHS
        case let (true, .notInExpr(parsedLHS, parsedRHS, _)):
            lhs = parsedLHS
            rhs = parsedRHS
        default:
            Issue.record("Expected the membership operator to own the whole expression")
            return
        }

        let callee: InternedString
        switch ast.arena.expr(lhs) {
        case let .memberCall(_, parsedCallee, _, _, _), let .safeMemberCall(_, parsedCallee, _, _, _):
            callee = parsedCallee
        default:
            Issue.record("Expected the left operand to be the trailing-lambda call")
            return
        }
        #expect(ctx.interner.resolve(callee) == "let")
        guard case let .nameRef(rhsName, _) = ast.arena.expr(rhs) else {
            Issue.record("Expected the right operand to remain in the membership expression")
            return
        }
        #expect(ctx.interner.resolve(rhsName) == "x")
    }
}
