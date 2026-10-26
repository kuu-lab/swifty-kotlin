#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericFunctionValueOverloadResolutionTests {
    @Test
    func functionTypeOverloadWinsWhenGenericValueOverloadInfersFunctionType() throws {
        let source = """
        fun <C : Any> choose(value: C): String = "value"
        fun <C : Any> choose(getValue: () -> C): String = "provider"

        fun main() {
            choose { "trailing" }
            choose({ "parenthesized" })
            choose("value")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let chooseCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .call(callee, _, _, _) = ast.arena.expr(exprID),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      ctx.interner.resolve(name) == "choose"
                else {
                    return nil
                }
                return exprID
            }
            #expect(chooseCalls.count == 3)

            for call in chooseCalls {
                let binding = try #require(sema.bindings.callBinding(for: call))
                let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
                guard let parameter = signature.parameterTypes.first else {
                    Issue.record("Expected choose overload to have one parameter")
                    continue
                }
                guard case let .call(_, _, arguments, _) = ast.arena.expr(call) else {
                    Issue.record("Expected choose call expression")
                    continue
                }
                let hasLambdaArgument = arguments.contains { argument in
                    if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                        return true
                    }
                    return false
                }
                if hasLambdaArgument {
                    guard case .functionType = sema.types.kind(of: parameter) else {
                        Issue.record("Expected lambda calls to select the function-typed overload")
                        continue
                    }
                } else {
                    guard case .typeParam = sema.types.kind(of: parameter) else {
                        Issue.record("Expected value calls to select the generic value overload")
                        continue
                    }
                }
            }
        }
    }

    @Test
    func functionTypeOverloadsCanStillBeAmbiguous() throws {
        let source = """
        fun ambiguous(block: () -> Int): Int = 1
        fun ambiguous(block: () -> String): String = "string"
        fun main() { ambiguous { 42 } }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1, "Expected ambiguity: \(errors)")
            #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "Unexpected no-viable-overload cascade: \(errors)")
            let ast = try #require(ctx.ast)
            let ambiguousCall = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .call(callee, _, _, _) = ast.arena.expr(exprID),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      ctx.interner.resolve(name) == "ambiguous"
                else {
                    return nil
                }
                return exprID
            }.first)
            #expect(ctx.sema?.bindings.callBinding(for: ambiguousCall)?.chosenCallee == nil)
        }
    }
}
#endif
