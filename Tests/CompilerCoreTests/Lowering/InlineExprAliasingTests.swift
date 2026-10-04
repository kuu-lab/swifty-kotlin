#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineExprAliasingTests {
    @Test
    func testResolveAliasReturnsExprUnchangedWhenMapIsEmpty() {
        let expr = KIRExprID(rawValue: 5)
        #expect(InlineExprAliasing.resolveAlias(of: expr, aliases: [:]) == expr)
    }

    @Test
    func testResolveAliasFollowsAChainToItsEnd() {
        let a = KIRExprID(rawValue: 1)
        let b = KIRExprID(rawValue: 2)
        let c = KIRExprID(rawValue: 3)
        #expect(InlineExprAliasing.resolveAlias(of: a, aliases: [a: b, b: c]) == c)
    }

    @Test
    func testResolveAliasStopsAtASelfAlias() {
        let a = KIRExprID(rawValue: 1)
        #expect(InlineExprAliasing.resolveAlias(of: a, aliases: [a: a]) == a)
    }

    // Traced by hand: a -> b (visited={a}) -> b -> a (visited={a,b}) -> a's
    // second visit fails `visited.insert(a).inserted`, so the loop exits
    // there and returns the starting expression, not `b`.
    @Test
    func testResolveAliasBreaksOutOfATwoCycleAtTheStartingExpr() {
        let a = KIRExprID(rawValue: 1)
        let b = KIRExprID(rawValue: 2)
        #expect(InlineExprAliasing.resolveAlias(of: a, aliases: [a: b, b: a]) == a)
    }

    @Test
    func testRewriteInstructionResolvesCallArgumentsButLeavesSymbolAndChannelsAlone() {
        let interner = StringInterner()
        let argument = KIRExprID(rawValue: 1)
        let resolvedArgument = KIRExprID(rawValue: 2)
        let result = KIRExprID(rawValue: 3)
        let thrown = KIRExprID(rawValue: 4)
        let symbol = SymbolID(rawValue: 10)
        let qualifier = SymbolID(rawValue: 11)
        let instruction = KIRInstruction.call(
            symbol: symbol, callee: interner.intern("target"),
            arguments: [argument], result: result, canThrow: true,
            thrownResult: thrown, isSuperCall: true, qualifiedSuperType: qualifier
        )

        let rewritten = InlineExprAliasing.rewriteInstruction(instruction, aliases: [argument: resolvedArgument])

        guard case let .call(rSymbol, rCallee, rArgs, rResult, rCanThrow, rThrown, rIsSuper, rQualifier) = rewritten else {
            Issue.record("Expected .call")
            return
        }
        #expect(rSymbol == symbol)
        #expect(rCallee == interner.intern("target"))
        #expect(rArgs == [resolvedArgument])
        #expect(rResult == result)
        #expect(rCanThrow)
        #expect(rThrown == thrown)
        #expect(rIsSuper)
        #expect(rQualifier == qualifier)
    }

    @Test
    func testRewriteInstructionResolvesVirtualCallReceiverAndArgumentsButKeepsDispatch() {
        let interner = StringInterner()
        let receiver = KIRExprID(rawValue: 1)
        let resolvedReceiver = KIRExprID(rawValue: 2)
        let argument = KIRExprID(rawValue: 3)
        let resolvedArgument = KIRExprID(rawValue: 4)
        let result = KIRExprID(rawValue: 5)
        let symbol = SymbolID(rawValue: 10)
        let dispatch = KIRDispatchKind.itableDynamic(interfaceTypeID: 77, methodSlot: 2)
        let instruction = KIRInstruction.virtualCall(
            symbol: symbol, callee: interner.intern("virtualTarget"),
            receiver: receiver, arguments: [argument], result: result,
            canThrow: false, thrownResult: nil, dispatch: dispatch
        )

        let rewritten = InlineExprAliasing.rewriteInstruction(
            instruction,
            aliases: [receiver: resolvedReceiver, argument: resolvedArgument]
        )

        guard case let .virtualCall(rSymbol, _, rReceiver, rArgs, rResult, _, _, rDispatch) = rewritten else {
            Issue.record("Expected .virtualCall")
            return
        }
        #expect(rSymbol == symbol)
        #expect(rReceiver == resolvedReceiver)
        #expect(rArgs == [resolvedArgument])
        #expect(rResult == result)
        #expect(rDispatch == dispatch)
    }

    @Test
    func testRewriteInstructionResolvesBothSidesOfACopy() {
        let from = KIRExprID(rawValue: 1)
        let to = KIRExprID(rawValue: 2)
        let resolvedFrom = KIRExprID(rawValue: 3)
        let resolvedTo = KIRExprID(rawValue: 4)

        let rewritten = InlineExprAliasing.rewriteInstruction(
            .copy(from: from, to: to),
            aliases: [from: resolvedFrom, to: resolvedTo]
        )

        #expect(rewritten == .copy(from: resolvedFrom, to: resolvedTo))
    }

    @Test
    func testRewriteInstructionLeavesLabelAndJumpTargetsUnchanged() {
        let aliases: [KIRExprID: KIRExprID] = [KIRExprID(rawValue: 1): KIRExprID(rawValue: 2)]
        #expect(InlineExprAliasing.rewriteInstruction(.label(7), aliases: aliases) == .label(7))
        #expect(InlineExprAliasing.rewriteInstruction(.jump(7), aliases: aliases) == .jump(7))
    }

    @Test
    func testDefinedResultReturnsTheWrittenExprForRegisterDefiningCases() {
        let result = KIRExprID(rawValue: 1)
        #expect(InlineExprAliasing.definedResult(in: .constValue(result: result, value: .unit)) == result)
        #expect(InlineExprAliasing.definedResult(in: .loadGlobal(result: result, symbol: SymbolID(rawValue: 1))) == result)
    }

    // `.copy`'s destination is intentionally not a "defined result" here --
    // it is invalidation state for a *different* alias map than the one the
    // copy itself writes through, matching current `expandInlineCalls`
    // behavior. `KIRVerifier`'s own def notion (`exprIsDefined` in
    // `InlineLoweringPass`) does count it; the two are deliberately not the
    // same set.
    @Test
    func testDefinedResultIgnoresACopysDestination() {
        let from = KIRExprID(rawValue: 1)
        let to = KIRExprID(rawValue: 2)
        #expect(InlineExprAliasing.definedResult(in: .copy(from: from, to: to)) == nil)
    }
}
#endif
