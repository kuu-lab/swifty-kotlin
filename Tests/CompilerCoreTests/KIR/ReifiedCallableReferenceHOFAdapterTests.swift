@testable import CompilerCore
import Testing

@Suite
struct ReifiedCallableReferenceHOFAdapterTests {
    @Test
    func markedTypedThunkDecodesReceiverAndTwoTokens() throws {
        let fixture = makeKIRDirectLoweringFixture()
        let functionType = fixture.types.make(.functionType(FunctionType(
            params: [fixture.types.stringType], returnType: fixture.types.stringType
        )))
        let reference = appendTypedExpr(
            .callableRef(receiver: nil, member: fixture.interner.intern("label"), range: makeRange()),
            type: functionType, fixture: fixture
        )
        fixture.bindings.markCollectionHOFLambdaExpr(reference)
        let target = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["typedReifiedThunk"])
        let callable = fixture.kirArena.appendExpr(.symbolRef(target), type: functionType)
        // Receiver plus two tokens must occupy distinct slots in the environment.
        let captures = [
            fixture.kirArena.appendExpr(.intLiteral(101), type: fixture.types.anyType),
            fixture.kirArena.appendExpr(.intLiteral(202), type: fixture.types.intType),
            fixture.kirArena.appendExpr(.intLiteral(303), type: fixture.types.intType),
        ]
        let result = fixture.kirArena.appendTemporary(type: fixture.types.stringType)
        _ = fixture.kirArena.appendDecl(.function(KIRFunction(
            symbol: target, name: fixture.interner.intern("typedReifiedThunk"),
            params: [fixture.types.anyType, fixture.types.intType, fixture.types.intType, fixture.types.stringType].map {
                KIRParameter(symbol: fixture.driver.ctx.allocateSyntheticGeneratedSymbol(), type: $0)
            }, returnType: fixture.types.stringType,
            body: [.beginBlock, .call(symbol: nil, callee: fixture.interner.intern("throwingTarget"),
                                     arguments: [], result: result, canThrow: true, thrownResult: nil),
                   .returnValue(result), .endBlock], isSuspend: false, isInline: false
        )))
        fixture.driver.ctx.registerCallableValue(
            callable, symbol: target, callee: fixture.interner.intern("typedReifiedThunk"),
            captureArguments: captures, hasClosureParam: false
        )
        var instructions: [KIRInstruction] = []
        let arguments = fixture.driver.callLowerer.addCollectionHOFClosureArguments(
            loweredArgIDs: [callable], argExprIDs: [reference], sema: fixture.sema,
            arena: fixture.kirArena, interner: fixture.interner, instructions: &instructions
        )
        #expect(arguments.count == 2)
        let adapted = try #require(fixture.driver.ctx.callableValueInfo(for: arguments[0]))
        #expect(adapted.hasClosureParam)
        #expect(adapted.symbol != target)
        #expect(adapted.captureArguments == captures)
        let functions = fixture.driver.ctx.drainGeneratedCallableDecls().compactMap { id -> KIRFunction? in
            guard case let .function(function)? = fixture.kirArena.decl(id) else { return nil }
            return function
        }
        let adapter = try #require(functions.first { $0.symbol == adapted.symbol })
        #expect(adapter.params.count == 2) // closureRaw + logical String argument
        let loads = adapter.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(_, callee, args, _, _, _, _, _) = instruction,
                  fixture.interner.resolve(callee) == "kk_array_get_inbounds" else { return nil }
            return args
        }
        #expect(loads.count == 3)
        let offsets = loads.compactMap { arguments -> Int64? in
            guard arguments.count == 2, case let .intLiteral(offset)? = fixture.kirArena.expr(arguments[1]) else { return nil }
            return offset
        }
        #expect(offsets == [2, 3, 4])
        let targetCall = try #require(adapter.body.first { instruction in
            if case let .call(symbol, _, _, _, _, _, _, _) = instruction { return symbol == target }
            return false
        })
        if case let .call(_, _, arguments, _, canThrow, _, _, _) = targetCall {
            #expect(arguments.count == 4) // decoded receiver + two tokens + logical argument
            #expect(Set(arguments.prefix(3)).count == 3)
            #expect(canThrow)
        }
    }
}
