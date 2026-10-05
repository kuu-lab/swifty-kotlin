@testable import CompilerCore
import Testing

@Suite
struct FunctionTypeIsCheckParsingTests {
    @Test(arguments: [
        "(Int) -> Int",
        "suspend (Int) -> Int",
        "Int.() -> Int",
        "suspend Int.() -> Int",
        "((Int) -> Int)?",
        "(Int) -> (Int) -> Int",
    ], ["is", "!is", "when-is", "when-!is"])
    func testFunctionTypeTarget(type: String, context: String) throws {
        let expression: String
        switch context {
        case "when-is": expression = "when (x) { is \(type) -> true; else -> false }"
        case "when-!is": expression = "when (x) { !is \(type) -> true; else -> false }"
        default: expression = "x \(context) \(type)"
        }
        let (ast, ctx) = try buildASTModule(
            from: "fun check(x: Any): Boolean = \(expression)",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let checks = ast.arena.exprs.compactMap { expr -> (TypeRefID, Bool)? in
            guard case let .isCheck(_, target, negated, _) = expr else { return nil }
            return (target, negated)
        }
        #expect(checks.count == 1)
        let (target, negated) = try #require(checks.first)
        #expect(negated == context.contains("!"))
        guard case let .functionType(_, receiver, params, result, isSuspend, nullable)? = ast.arena.typeRef(target) else {
            Issue.record("Expected a function type target")
            return
        }
        #expect(isSuspend == type.hasPrefix("suspend"))
        #expect((receiver != nil) == type.contains(".()"))
        #expect(params.count == (receiver == nil ? 1 : 0))
        #expect(nullable == type.hasSuffix("?"))
        if type == "(Int) -> (Int) -> Int" {
            guard case .functionType? = ast.arena.typeRef(result) else {
                Issue.record("Expected a nested function return type")
                return
            }
        }
        if context.hasPrefix("when") {
            let whenExpr = try #require(ast.arena.exprs.first { if case .whenExpr = $0 { return true }; return false })
            guard case let .whenExpr(_, branches, elseExpr, _) = whenExpr else { return }
            #expect(branches.count == 1)
            #expect(elseExpr != nil)
            guard case .boolLiteral(true, _)? = ast.arena.expr(try #require(branches.first).body) else {
                Issue.record("The branch arrow must remain separate from the function type")
                return
            }
        }
    }
}
