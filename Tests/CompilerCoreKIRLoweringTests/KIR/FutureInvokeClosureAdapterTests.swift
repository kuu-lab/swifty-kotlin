#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct FutureInvokeClosureAdapterTests {
    @Test(arguments: [false, true])
    func callbackExpandsToFunctionAndEnvironment(knownCallable: Bool) throws {
        let fixture = makeKIRDirectLoweringFixture()
        let functionType = fixture.types.make(.functionType(FunctionType(
            params: [fixture.types.anyType], returnType: fixture.types.anyType,
            isSuspend: false, nullability: .nonNull
        )))
        let source = appendTypedExpr(.nameRef(fixture.interner.intern("code"), makeRange()),
            type: functionType, fixture: fixture)
        let valueSource = appendTypedExpr(.intLiteral(42, makeRange()),
            type: fixture.types.anyType, fixture: fixture)
        let callable = fixture.kirArena.appendTemporary(type: functionType)
        let value = fixture.kirArena.appendTemporary(type: fixture.types.anyType)
        let environment = fixture.kirArena.appendTemporary(type: fixture.types.anyType)
        let function = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["test", "callback"])
        if knownCallable {
            fixture.driver.ctx.registerCallableValue(callable, symbol: function,
                callee: fixture.interner.intern("callback"), captureArguments: [environment], hasClosureParam: true)
        }
        let bridge = defineSemanticSymbol(in: fixture, kind: .function,
            fqName: ["kotlin", "native", "concurrent", "__kkFutureInvoke"])
        fixture.symbols.setExternalLinkName("kk_future_invoke", for: bridge)
        var instructions: [KIRInstruction] = []
        let expanded = fixture.driver.callLowerer.appendClosureArgumentsIfNeeded(
            [callable, value], originalArgs: [CallArgument(expr: source), CallArgument(expr: valueSource)],
            chosenCallee: bridge, sema: fixture.sema, arena: fixture.kirArena,
            interner: fixture.interner, instructions: &instructions
        )
        #expect(expanded.count == 3)
        #expect(expanded.last == value)
        if knownCallable {
            #expect(fixture.kirArena.expr(expanded[0]) == .symbolRef(function))
            #expect(expanded[1] == environment)
        } else {
            #expect(expanded[1] == callable)
            guard case let .symbolRef(adapterSymbol)? = fixture.kirArena.expr(expanded[0]) else {
                Issue.record("Expected a forwarded callback adapter")
                return
            }
            let adapter = try #require(fixture.kirArena.function(for: adapterSymbol))
            #expect(adapter.params.count == 2)
            let invoke = try #require(kirCalls(in: adapter.body).first)
            #expect(fixture.interner.resolve(invoke.callee) == "kk_function_invoke")
            #expect(invoke.arguments.count == 2)
            #expect(invoke.canThrow)
            let thrown = try #require(invoke.thrownResult)
            #expect(adapter.body.contains(.rethrow(value: thrown)))
        }
    }

    @Test
    func ordinaryHomonymDoesNotExpand() {
        let fixture = makeKIRDirectLoweringFixture()
        let source = appendTypedExpr(.intLiteral(0, makeRange()), type: fixture.types.anyType, fixture: fixture)
        let arguments = (0..<2).map { _ in fixture.kirArena.appendTemporary(type: fixture.types.anyType) }
        let function = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["user", "__kkFutureInvoke"])
        var instructions: [KIRInstruction] = []
        let expanded = fixture.driver.callLowerer.appendClosureArgumentsIfNeeded(
            arguments, originalArgs: [CallArgument(expr: source), CallArgument(expr: source)],
            chosenCallee: function, sema: fixture.sema, arena: fixture.kirArena,
            interner: fixture.interner, instructions: &instructions
        )
        #expect(expanded == arguments)
        #expect(instructions.isEmpty)
    }
}
#endif
