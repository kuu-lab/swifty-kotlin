#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExplicitContextArgumentTests {
    @Test
    func namedContextArgumentMapsAndLowersToContextSlot() throws {
        let source = """
        context(c: Int)
        fun render(v: String): String = "$c$v"
        fun caller(): String = render(c = 1, v = "OK")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let call = try call(named: "render", path: path, in: ctx)
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.contextParameterArgumentMapping == [0: 0])
            #expect(binding.parameterMapping == [1: 0])

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "caller", in: module, interner: ctx.interner)
            let callInstruction = try #require(body.first { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == binding.chosenCallee
            })
            guard case let .call(_, _, arguments, _, _, _, _, _) = callInstruction else {
                Issue.record("Expected the render call in caller's KIR body.")
                return
            }
            #expect(arguments.compactMap(module.arena.exprType) == [sema.types.intType, sema.types.stringType])
        }
    }

    @Test
    func incompatibleExplicitContextArgumentDoesNotReportMissingContext() throws {
        let source = """
        context(c: Int)
        fun render(v: String) {}
        fun caller() { render(c = "wrong", v = "OK") }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-CTX-002" })
        }
    }

    @Test
    func explicitContextArgumentDisambiguatesAgainstValueParameterOverload() throws {
        let source = """
        open class Parent
        class Child : Parent()
        fun choose(x: Parent): String = "value"
        context(x: Child) fun choose(): String = "context"
        fun caller(): String = choose(x = Child())
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let call = try call(named: "choose", path: path, in: ctx)
            let binding = try #require(sema.bindings.callBinding(for: call))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            let child = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Child")]))
            #expect(signature.contextParameterTypes == [sema.types.make(.classType(ClassType(
                classSymbol: child, args: [], nullability: .nonNull
            )))])
            #expect(binding.contextParameterArgumentMapping == [0: 0])
            #expect(binding.parameterMapping.isEmpty)
        }
    }

    @Test
    func explicitContextArgumentKeepsSourceEvaluationOrder() throws {
        let source = """
        context(c: Int)
        fun render(v: String): String = "$c$v"
        fun contextValue(): Int = 1
        fun value(): String = "OK"
        fun caller(): String = render(v = value(), c = contextValue())
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "caller", in: module, interner: ctx.interner)
            let calledSymbols = body.compactMap { instruction -> SymbolID? in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return nil }
                return symbol
            }
            let valueSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("value")]))
            let contextValueSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("contextValue")]))
            let call = try call(named: "render", path: path, in: ctx)
            let renderSymbol = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            guard let valueIndex = calledSymbols.firstIndex(of: valueSymbol),
                  let contextIndex = calledSymbols.firstIndex(of: contextValueSymbol),
                  let renderIndex = calledSymbols.firstIndex(of: renderSymbol)
            else {
                Issue.record("Expected both argument producers and render in caller's KIR body.")
                return
            }
            #expect(valueIndex < contextIndex && contextIndex < renderIndex)
        }
    }

    private func call(named name: String, path: String, in ctx: CompilationContext) throws -> ExprID {
        let ast = try #require(ctx.ast)
        let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee)
            else { return false }
            return ctx.interner.resolve(calleeName) == name
        }
        #expect(calls.count == 1)
        return try #require(calls.first)
    }
}
#endif
