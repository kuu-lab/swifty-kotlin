#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SafeCallAssignmentLambdaUnitInferenceTests {
    @Test
    func infersUnitForStoredSafeCallPropertyAssignmentLambda() throws {
        let source = """
        class Wrapper(var s: String)
        fun accept(action: () -> Unit) { action() }
        fun box(): String {
            val w: Wrapper? = Wrapper("Test")
            val action = safeAssignment@{ w?.s = "X" }
            accept(action)
            return "OK"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let lambdas = allExprIDs(in: ast, path: path, ctx: ctx) { id, expr in
                guard sema.bindings.exprType(for: id) != nil,
                      case let .lambdaLiteral(_, _, label?, _) = expr
                else {
                    return false
                }
                return ctx.interner.resolve(label) == "safeAssignment"
            }
            #expect(lambdas.count == 1)

            guard let lambda = lambdas.first,
                  let lambdaType = sema.bindings.exprType(for: lambda)
            else {
                Issue.record("Expected the labeled lambda to have an inferred type")
                return
            }
            guard case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(lambda),
                  case let .blockExpr(statements, trailingExpr, _) = ast.arena.expr(body),
                  statements.count == 1,
                  trailingExpr == nil,
                  case .safeMemberAssign = ast.arena.expr(statements[0])
            else {
                Issue.record("Expected the lambda body to contain a safe member assignment")
                return
            }
            #expect(sema.bindings.exprType(for: statements[0]) == sema.types.unitType)
            guard case let .functionType(function) = sema.types.kind(of: lambdaType) else {
                Issue.record("Expected an inferred function type, got \(sema.types.renderType(lambdaType))")
                return
            }
            #expect(function.params.isEmpty)
            #expect(
                function.returnType == sema.types.unitType,
                "Expected Unit, got \(sema.types.renderType(function.returnType)) from \(String(describing: ast.arena.expr(lambda)))"
            )
        }
    }

    @Test
    func keepsExpectedUnitAndValueReturningLambdaInference() throws {
        let source = """
        class Wrapper(var s: String)
        fun consume(action: () -> Unit) {}
        fun consumeInt(action: () -> Int) {}
        fun check(w: Wrapper?, nonNull: Wrapper) {
            val typed: () -> Unit = { w?.s = "X" }
            consume(typed)
            consume { w?.s = "Y" }
            val plain = { nonNull.s = "Z" }
            consume(plain)
            val value = value@{ 42 }
            consumeInt(value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let valueLambdas = allExprIDs(in: ast, path: path, ctx: ctx) { id, expr in
                guard sema.bindings.exprType(for: id) != nil,
                      case let .lambdaLiteral(_, _, label?, _) = expr
                else {
                    return false
                }
                return ctx.interner.resolve(label) == "value"
            }
            #expect(valueLambdas.count == 1)

            guard let lambda = valueLambdas.first,
                  let lambdaType = sema.bindings.exprType(for: lambda)
            else {
                Issue.record("Expected the value lambda to have an inferred type")
                return
            }
            guard case let .functionType(function) = sema.types.kind(of: lambdaType) else {
                Issue.record("Expected an inferred function type, got \(sema.types.renderType(lambdaType))")
                return
            }
            #expect(function.returnType == sema.types.intType)
        }
    }
}
#endif
