@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct FunctionTypeAsCastParsingTests {
    @Test(arguments: [
        "() -> Int",
        "(Int) -> Int",
        "(Int, String) -> Boolean",
        "suspend (Int) -> Int",
        "Int.() -> Int",
        "suspend Int.() -> Int",
        "((Int) -> Int)?",
        "(Int) -> (Int) -> Int",
    ], ["as", "as?"])
    func functionTypeCastTarget(type: String, castOperator: String) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun check(x: Any): Any = x \(castOperator) \(type)",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let casts = ast.arena.exprs.compactMap { expr -> (TypeRefID, Bool)? in
            guard case let .asCast(_, target, isSafe, _) = expr else { return nil }
            return (target, isSafe)
        }
        let (target, isSafe) = try #require(casts.first)
        #expect(casts.count == 1)
        #expect(isSafe == castOperator.hasSuffix("?"))
        guard case let .functionType(_, receiver, params, result, isSuspend, nullable)? = ast.arena.typeRef(target) else {
            Issue.record("Expected a function type target")
            return
        }
        #expect(isSuspend == type.hasPrefix("suspend"))
        #expect((receiver != nil) == type.contains(".()"))
        #expect(params.isEmpty == type.hasPrefix("() ->") || type.contains(".()"))
        #expect(nullable == type.hasSuffix("?"))
        if type == "(Int) -> (Int) -> Int" {
            guard case .functionType? = ast.arena.typeRef(result) else {
                Issue.record("Expected a nested function return type")
                return
            }
        }
    }

    @Test(arguments: [
        "println(foo@{ 7 } as () -> Int)",
        "println((foo@{ 7 }) as () -> Int)",
        "println({ 7 } as () -> Int)",
        "println(foo@{ 7 } as? () -> Int)",
        "println(foo@{ 7 } as Any)",
        "foo(lbl@{ it } as (Int) -> Int)",
    ])
    func callArgumentLambdaCast(call: String) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun main() { \(call) }",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let casts = ast.arena.exprs.compactMap { expr -> (ExprID, TypeRefID, Bool)? in
            guard case let .asCast(operand, target, isSafe, _) = expr else { return nil }
            return (operand, target, isSafe)
        }
        let (operand, target, _) = try #require(casts.first)
        #expect(casts.count == 1)
        if call.contains("->") {
            guard case .functionType? = ast.arena.typeRef(target) else {
                Issue.record("Expected a function type cast target")
                return
            }
        }
        if call.hasPrefix("println(foo@") || call.hasPrefix("foo(lbl@") {
            guard case let .lambdaLiteral(_, _, label?, _)? = ast.arena.expr(operand) else {
                Issue.record("Expected the cast operand to be the labeled lambda")
                return
            }
            let expectedLabel = call.contains("foo@") ? "foo" : "lbl"
            #expect(ctx.interner.resolve(label) == expectedLabel)
        }
    }

    @Test
    func castTargetConsumesParenthesizedFunctionArrow() throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun check(x: Any): Any = x as (Boolean) -> Any",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let casts = ast.arena.exprs.compactMap { expr -> TypeRefID? in
            guard case let .asCast(_, target, _, _) = expr else { return nil }
            return target
        }
        let target = try #require(casts.first)
        guard case let .functionType(_, _, params, _, _, _)? = ast.arena.typeRef(target) else {
            Issue.record("Expected `(Boolean) -> Any` to parse as a function type")
            return
        }
        #expect(params.count == 1)
    }
}
