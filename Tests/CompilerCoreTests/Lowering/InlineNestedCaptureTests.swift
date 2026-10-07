#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineNestedCaptureTests {
    @Test(arguments: [false, true])
    func clonedCapturesRemainAvailableToCoroutineLowering(hasCallableInfo: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbol = SymbolID(rawValue: 1)
        let name = interner.intern("capturedBlock")
        let source = arena.appendExpr(.symbolRef(symbol), type: types.anyType)
        let capture = arena.appendTemporary(type: types.intType)
        let first = arena.appendExpr(.intLiteral(7), type: types.intType)
        let second = arena.appendExpr(.intLiteral(11), type: types.intType)
        let firstClone = arena.appendExpr(.symbolRef(symbol), type: types.anyType)
        let secondClone = arena.appendExpr(.symbolRef(symbol), type: types.anyType)
        arena.registerLambdaCaptureArgs(symbol, captureArgs: [capture])
        _ = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: name, params: [], returnType: types.unitType,
            body: [.returnUnit], isSuspend: true, isInline: false
        )))
        if hasCallableInfo {
            arena.callableValueInfoByExprID[source] = KIRCallableValueInfo(
                symbol: symbol, callee: name, captureArguments: [capture], hasClosureParam: true
            )
        }
        let pass = InlineLoweringPass()
        pass.recordClonedLambdaCaptures(
            source: source, cloned: firstClone, value: .symbolRef(symbol),
            aliases: [capture: first], arena: arena
        )
        pass.recordClonedLambdaCaptures(
            source: source, cloned: secondClone, value: .symbolRef(symbol),
            aliases: [capture: second], arena: arena
        )
        let firstInfo = try #require(arena.callableValueInfo(for: firstClone))
        let secondInfo = try #require(arena.callableValueInfo(for: secondClone))
        #expect(firstInfo.captureArguments == [first])
        #expect(secondInfo.captureArguments == [second])
        #expect(firstInfo.hasClosureParam == hasCallableInfo)
        #expect(secondInfo.hasClosureParam == hasCallableInfo)
        #expect(arena.lambdaCaptureArgsBySymbol[symbol] == [capture])
    }

    @Test(arguments: [false, true], [false, true])
    func lambdaReturnsCallerArgument(captured: Bool, bodylessSnapshot: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let lambdaSymbol = SymbolID(rawValue: 1)
        let visitSymbol = SymbolID(rawValue: 2)
        let captureParam = SymbolID(rawValue: 11)
        let lambdaParam = SymbolID(rawValue: 12)
        let valueParam = SymbolID(rawValue: 13)
        let actionParam = SymbolID(rawValue: 14)
        func ref(_ symbol: SymbolID) -> KIRExprID {
            arena.appendExpr(.symbolRef(symbol), type: types.intType)
        }
        func function(
            _ symbol: SymbolID, _ name: String, _ params: [SymbolID],
            _ body: [KIRInstruction], inline: Bool = false, bodyless: Bool = false
        ) -> KIRFunction {
            KIRFunction(
                symbol: symbol, name: interner.intern(name),
                params: params.map { KIRParameter(symbol: $0, type: types.intType) },
                returnType: types.intType, body: body, isSuspend: false,
                isInline: inline, isInlineOnly: bodyless
            )
        }
        let returnedParam = captured ? captureParam : lambdaParam
        let returnedValue = ref(returnedParam)
        let lambda = function(lambdaSymbol, "lambda", captured ? [captureParam, lambdaParam] : [lambdaParam], [
            .constValue(result: returnedValue, value: .symbolRef(returnedParam)),
            .returnValue(returnedValue),
        ])
        let value = ref(valueParam)
        let action = ref(actionParam)
        let visitResult = arena.appendTemporary(type: types.intType)
        let visit = function(visitSymbol, "visit", [valueParam, actionParam], [
            .constValue(result: value, value: .symbolRef(valueParam)),
            .constValue(result: action, value: .symbolRef(actionParam)),
            .call(symbol: nil, callee: interner.intern("kk_function_invoke"),
                  arguments: [action, value], result: visitResult, canThrow: false, thrownResult: nil),
            .returnValue(visitResult),
        ], inline: true, bodyless: bodylessSnapshot)
        let seven = arena.appendExpr(.intLiteral(7), type: types.intType)
        let eleven = arena.appendExpr(.intLiteral(11), type: types.intType)
        if captured { arena.registerLambdaCaptureArgs(lambdaSymbol, captureArgs: [seven]) }
        let lambdaRef = ref(lambdaSymbol)
        let result = arena.appendTemporary(type: types.intType)
        let caller = function(SymbolID(rawValue: 3), "caller", [], [
            .constValue(result: seven, value: .intLiteral(7)),
            .constValue(result: eleven, value: .intLiteral(11)),
            .constValue(result: lambdaRef, value: .symbolRef(lambdaSymbol)),
            .call(symbol: visitSymbol, callee: visit.name, arguments: [eleven, lambdaRef],
                  result: result, canThrow: false, thrownResult: nil),
            .returnValue(result),
        ])
        let callerID = arena.appendDecl(.function(caller))
        for fn in [visit, lambda] { _ = arena.appendDecl(.function(fn)) }
        let module = KIRModule(files: [], arena: arena)
        let context = makeCompilationContext(inputs: [], includeStdlib: false)
        try InlineLoweringPass().run(module: module, ctx: KIRContext(
            diagnostics: context.diagnostics, options: context.options, interner: interner
        ))
        #expect(!context.diagnostics.hasError)
        let lowered = try #require(arena.decl(callerID)?.function)
        let copies = lowered.body.compactMap { instruction -> KIRExprID? in
            guard case let .copy(from, _) = instruction else { return nil }
            return from
        }
        #expect(copies.contains(captured ? seven : eleven))
        #expect(!lowered.body.contains { if case .constValue(_, .unit) = $0 { true } else { false } })
    }

    @Test(arguments: [false, true], [false, true])
    func nestedCapturesUseCallerSlots(nonLocalReturn: Bool, bodylessSnapshot: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let outerSymbol = SymbolID(rawValue: 1)
        let innerSymbol = SymbolID(rawValue: 2)
        let visitSymbol = SymbolID(rawValue: 3)
        let offsetSymbol = SymbolID(rawValue: 4)
        let outerParam = SymbolID(rawValue: 11)
        let captureParam = SymbolID(rawValue: 12)
        let offsetParam = SymbolID(rawValue: 13)
        let valueParam = SymbolID(rawValue: 14)
        let actionParam = SymbolID(rawValue: 15)
        let blockParam = SymbolID(rawValue: 16)
        func ref(_ symbol: SymbolID) -> KIRExprID {
            arena.appendExpr(.symbolRef(symbol), type: types.intType)
        }
        func invoke(_ args: [KIRExprID], result: KIRExprID) -> KIRInstruction {
            .call(symbol: nil, callee: interner.intern("kk_function_invoke"),
                  arguments: args, result: result, canThrow: false, thrownResult: nil)
        }
        func function(
            _ symbol: SymbolID, _ name: String, _ params: [SymbolID],
            _ body: [KIRInstruction], inline: Bool = false, bodyless: Bool = false
        ) -> KIRFunction {
            KIRFunction(
                symbol: symbol, name: interner.intern(name),
                params: params.map { KIRParameter(symbol: $0, type: types.intType) },
                returnType: types.intType, body: body, isSuspend: false,
                isInline: inline, isInlineOnly: bodyless
            )
        }

        let outerValue = ref(outerParam)
        let capture = ref(captureParam)
        let offset = ref(offsetParam)
        let sum = arena.appendTemporary(type: types.intType)
        let innerRef = ref(innerSymbol)
        arena.registerLambdaCaptureArgs(innerSymbol, captureArgs: [outerValue])
        let inner = function(innerSymbol, "inner", [captureParam, offsetParam], [
            .constValue(result: capture, value: .symbolRef(captureParam)),
            .constValue(result: offset, value: .symbolRef(offsetParam)),
            .binary(op: .add, lhs: capture, rhs: offset, result: sum),
            nonLocalReturn ? .nonLocalReturn(sum) : .returnValue(sum),
        ])

        let block = ref(blockParam)
        let three = arena.appendExpr(.intLiteral(3), type: types.intType)
        let offsetResult = arena.appendTemporary(type: types.intType)
        let withOffset = function(offsetSymbol, "withOffset", [blockParam], [
            .constValue(result: block, value: .symbolRef(blockParam)),
            .constValue(result: three, value: .intLiteral(3)),
            invoke([block, three], result: offsetResult),
            .returnValue(offsetResult),
        ], inline: true, bodyless: bodylessSnapshot)
        let outerResult = arena.appendTemporary(type: types.intType)
        let outer = function(outerSymbol, "outer", [outerParam], [
            .constValue(result: outerValue, value: .symbolRef(outerParam)),
            .constValue(result: innerRef, value: .symbolRef(innerSymbol)),
            .call(symbol: offsetSymbol, callee: withOffset.name, arguments: [innerRef],
                  result: outerResult, canThrow: false, thrownResult: nil),
            .returnValue(outerResult),
        ])

        let value = ref(valueParam)
        let action = ref(actionParam)
        let visitResult = arena.appendTemporary(type: types.intType)
        let visit = function(visitSymbol, "visit", [valueParam, actionParam], [
            .constValue(result: value, value: .symbolRef(valueParam)),
            .constValue(result: action, value: .symbolRef(actionParam)),
            invoke([action, value], result: visitResult),
            .returnValue(visitResult),
        ], inline: true)

        let outerRef = ref(outerSymbol)
        let seven = arena.appendExpr(.intLiteral(7), type: types.intType)
        let eleven = arena.appendExpr(.intLiteral(11), type: types.intType)
        let firstResult = arena.appendTemporary(type: types.intType)
        let secondResult = arena.appendTemporary(type: types.intType)
        let caller = function(SymbolID(rawValue: 5), "caller", [], [
            .constValue(result: seven, value: .intLiteral(7)),
            .constValue(result: eleven, value: .intLiteral(11)),
            .constValue(result: outerRef, value: .symbolRef(outerSymbol)),
            .call(symbol: visitSymbol, callee: visit.name, arguments: [seven, outerRef],
                  result: firstResult, canThrow: false, thrownResult: nil),
            .call(symbol: visitSymbol, callee: visit.name, arguments: [eleven, outerRef],
                  result: secondResult, canThrow: false, thrownResult: nil),
            .returnValue(secondResult),
        ])
        let callerID = arena.appendDecl(.function(caller))
        for fn in [visit, withOffset, outer, inner] { _ = arena.appendDecl(.function(fn)) }
        let module = KIRModule(files: [], arena: arena)
        let context = makeCompilationContext(inputs: [], includeStdlib: false)
        try InlineLoweringPass().run(module: module, ctx: KIRContext(
            diagnostics: context.diagnostics, options: context.options, interner: interner
        ))
        #expect(!context.diagnostics.hasError)
        let lowered = try #require(arena.decl(callerID)?.function)
        let sums = lowered.body.compactMap { instruction -> (KIRExprID, KIRExprID)? in
            guard case let .binary(.add, lhs, rhs, _) = instruction else { return nil }
            return (lhs, rhs)
        }
        #expect(sums.map { $0.0 } == [seven, eleven])
        #expect(sums.allSatisfy { arena.expr($0.1) == .intLiteral(3) })
        #expect(arena.lambdaCaptureArgsBySymbol[innerSymbol] == [outerValue])
        #expect(!lowered.body.contains { if case .nonLocalReturn = $0 { true } else { false } })
        #expect(!lowered.body.contains { if case .call = $0 { true } else { false } })
    }
}
#endif
