@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct TrailingLambdaPostfixOperatorTests {
    private func nullAssertedCallee(
        named expected: String,
        in ast: ASTModule,
        body: FunctionBody,
        interner: StringInterner
    ) {
        guard case let .expr(bodyExpression, _) = body else {
            Issue.record("Expected an expression-bodied declaration")
            return
        }
        guard case let .nullAssert(asserted, _) = ast.arena.expr(bodyExpression) else {
            Issue.record("Expected `!!` to own the whole expression")
            return
        }
        guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(asserted) else {
            Issue.record("Expected the asserted expression to be the trailing-lambda call")
            return
        }
        #expect(interner.resolve(callee) == expected)
    }

    @Test(arguments: [
        "fun test(c: String?) = c.let { it.toInt() }!!",
        "val String?.test get() = this.let { it.toInt() }!!",
        "fun String?.test() = this.let { it.toInt() }!!",
    ])
    func notNullAssertionContinuesPastTrailingLambda(declaration: String) throws {
        let (ast, ctx) = try buildASTModule(from: declaration, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        for file in ast.files where ctx.sourceManager.origin(of: file.fileID) == .user {
            #expect(file.scriptBody.isEmpty, "`!!` after a trailing lambda must not be re-parsed as a top-level statement")
        }

        if let function = topLevelFunction(named: "test", in: ast, interner: ctx.interner) {
            nullAssertedCallee(named: "let", in: ast, body: function.body, interner: ctx.interner)
        } else if let property = topLevelProperty(named: "test", in: ast, interner: ctx.interner),
                  let getter = property.getter {
            nullAssertedCallee(named: "let", in: ast, body: getter.body, interner: ctx.interner)
        } else {
            Issue.record("Expected a `test` declaration")
        }
    }

    @Test(arguments: [
        "c.let { it.toInt() } !is Int",
        "c?.let { it.toInt() } !is Int",
    ])
    func notIsContinuesPastTrailingLambda(expression: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun test(c: String?) = \(expression)
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let function = try #require(topLevelFunction(named: "test", in: ast, interner: ctx.interner))
        guard case let .expr(bodyExpression, _) = function.body else {
            Issue.record("Expected an expression-bodied function")
            return
        }
        guard case let .isCheck(lhs, _, negated, _) = ast.arena.expr(bodyExpression) else {
            Issue.record("Expected the `!is` check to own the whole expression")
            return
        }
        #expect(negated)

        let callee: InternedString
        switch ast.arena.expr(lhs) {
        case let .memberCall(_, parsedCallee, _, _, _), let .safeMemberCall(_, parsedCallee, _, _, _):
            callee = parsedCallee
        default:
            Issue.record("Expected the left operand to be the trailing-lambda call")
            return
        }
        #expect(ctx.interner.resolve(callee) == "let")
    }
}
