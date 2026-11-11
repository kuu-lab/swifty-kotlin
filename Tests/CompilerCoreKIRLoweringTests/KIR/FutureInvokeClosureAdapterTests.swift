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
            let calls = kirCalls(in: instructions)
            #expect(calls.map { fixture.interner.resolve($0.callee) } == [
                "kk_function_value_fn_ptr", "kk_function_value_closure_raw",
            ])
            #expect(calls.allSatisfy { $0.arguments == [callable] })
            #expect(calls.map(\.result) == expanded.prefix(2).map(Optional.some))
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
