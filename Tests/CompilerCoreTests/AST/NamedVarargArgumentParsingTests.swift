#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NamedVarargArgumentParsingTests {
    @Test(arguments: [
        ("xs = values", true, false),
        ("xs = *values", true, true),
        ("*values", false, true),
    ])
    func preservesArgumentLabelAndSpread(
        argument: String, named: Bool, spread: Bool
    ) throws {
        let (ast, ctx) = try buildASTModule(
            from: "fun main() = h(\(argument))", includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError)
        let function = try #require(firstFunDecl(named: "main", in: ast, interner: ctx.interner))
        guard case let .expr(body, _) = function.body,
              case let .call(_, _, args, _) = ast.arena.expr(body)
        else {
            Issue.record("Expected the function body to remain a call")
            return
        }
        #expect(args.count == 1)
        let arg = try #require(args.first)
        #expect(arg.label.map { ctx.interner.resolve($0) } == (named ? "xs" : nil))
        #expect(arg.isSpread == spread)
        guard case let .nameRef(value, _) = ast.arena.expr(arg.expr) else {
            Issue.record("Expected the array expression to remain the argument")
            return
        }
        #expect(ctx.interner.resolve(value) == "values")
    }
}
#endif
