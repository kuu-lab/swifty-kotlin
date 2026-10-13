#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AtomicfuParkingClosureAdapterTests {
    @Test(arguments: [0, 1, 2])
    func factoryHasEnvironmentAndSeparateThrownChannel(captureCount: Int) throws {
        let fixture = makeKIRDirectLoweringFixture()
        let functionType = fixture.types.make(.functionType(FunctionType(
            params: [], returnType: fixture.types.anyType,
            isSuspend: false, nullability: .nonNull
        )))
        let source = appendTypedExpr(.nameRef(fixture.interner.intern("factory"), makeRange()),
            type: functionType, fixture: fixture)
        let callable = fixture.kirArena.appendTemporary(type: functionType)
        let factory = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "factory"])
        let captures = (0..<captureCount).map { _ in
            fixture.kirArena.appendTemporary(type: fixture.types.anyType)
        }
        let thrown = fixture.kirArena.appendTemporary(type: fixture.types.nullableAnyType)
        _ = fixture.kirArena.appendDecl(.function(KIRFunction(
            symbol: factory, name: fixture.interner.intern("factory"),
            params: captures.map { _ in KIRParameter(
                symbol: fixture.driver.ctx.allocateSyntheticGeneratedSymbol(), type: fixture.types.anyType) },
            returnType: fixture.types.anyType, body: [.beginBlock, .rethrow(value: thrown), .endBlock],
            isSuspend: false, isInline: false
        )))
        fixture.driver.ctx.registerCallableValue(callable, symbol: factory,
            callee: fixture.interner.intern("factory"), captureArguments: captures, hasClosureParam: false)
        let bridge = defineSemanticSymbol(in: fixture, kind: .function,
            fqName: ["kotlinx", "atomicfu", "locks", "atomicfuCurrentParkingHandle"])
        fixture.symbols.setExternalLinkName("__kk_atomicfu_current_parking_handle", for: bridge)
        var instructions: [KIRInstruction] = []
        let expanded = fixture.driver.callLowerer.appendClosureArgumentsIfNeeded(
            [callable], originalArgs: [CallArgument(expr: source)], chosenCallee: bridge,
            sema: fixture.sema, arena: fixture.kirArena, interner: fixture.interner,
            instructions: &instructions)
        #expect(expanded.count == 2)
        guard case let .symbolRef(adapterSymbol)? = fixture.kirArena.expr(expanded[0]) else {
            Issue.record("Expected actual closure-thunk adapter pointer")
            return
        }
        #expect(adapterSymbol != factory)
        let adapter = try #require(fixture.kirArena.function(for: adapterSymbol))
        // One explicit env word plus the separately lowered outThrown channel.
        #expect(adapter.params.count == 1)
        #expect(adapter.params[0].type == fixture.types.intType)
        #expect(adapter.returnType == fixture.types.anyType)
        let call = try #require(kirCalls(in: adapter.body).first { $0.symbol == factory })
        #expect(call.arguments.count == captureCount)
        #expect(call.canThrow)
        #expect(call.thrownResult != nil)
        #expect(adapter.body.contains { if case .rethrow = $0 { return true }; return false })
    }

    @Test func ordinaryHomonymAndNearMatchDoNotExpand() {
        let fixture = makeKIRDirectLoweringFixture()
        let source = appendTypedExpr(.intLiteral(0, makeRange()), type: fixture.types.anyType, fixture: fixture)
        let value = fixture.kirArena.appendTemporary(type: fixture.types.anyType)
        for link in [nil, "__kk_atomicfu_current_parking_handle_other"] as [String?] {
            let ordinary = defineSemanticSymbol(in: fixture, kind: .function,
                fqName: ["user", link == nil ? "atomicfuCurrentParkingHandle" : "nearMatch"])
            if let link { fixture.symbols.setExternalLinkName(link, for: ordinary) }
            var instructions: [KIRInstruction] = []
            let result = fixture.driver.callLowerer.appendClosureArgumentsIfNeeded(
                [value], originalArgs: [CallArgument(expr: source)], chosenCallee: ordinary,
                sema: fixture.sema, arena: fixture.kirArena, interner: fixture.interner,
                instructions: &instructions)
            #expect(result == [value])
            #expect(instructions.isEmpty)
        }
    }
}
#endif
