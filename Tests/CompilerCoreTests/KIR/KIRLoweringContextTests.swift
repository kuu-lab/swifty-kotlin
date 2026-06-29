#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite @MainActor
struct KIRLoweringContextTests {
    let ctx = KIRLoweringContext()

    // MARK: - Scope Management: saveScope / restoreScope

    @Test func testSaveScopeReturnsSnapshotOfCurrentState() {
        ctx.localValuesBySymbol[SymbolID(rawValue: 1)] = KIRExprID(rawValue: 10)
        ctx.currentImplicitReceiverExprID = KIRExprID(rawValue: 5)
        ctx.currentImplicitReceiverSymbol = SymbolID(rawValue: 2)
        ctx.loopControlStack = [(continueLabel: 100, breakLabel: 200, name: nil)]
        ctx.nextLoopLabel = 20000

        let snapshot = ctx.saveScope()

        #expect(snapshot.localValuesBySymbol[SymbolID(rawValue: 1)] == KIRExprID(rawValue: 10))
        #expect(snapshot.currentImplicitReceiverExprID == KIRExprID(rawValue: 5))
        #expect(snapshot.currentImplicitReceiverSymbol == SymbolID(rawValue: 2))
        #expect(snapshot.loopControlStack.count == 1)
        #expect(snapshot.loopControlStack[0].continueLabel == 100)
        #expect(snapshot.loopControlStack[0].breakLabel == 200)
        #expect(snapshot.loopControlStack[0].name == nil)
        #expect(snapshot.nextLoopLabel == 20000)
    }

    @Test func testRestoreScopeRevertsAllScopeProperties() {
        let snapshot = ctx.saveScope()
        ctx.localValuesBySymbol[SymbolID(rawValue: 99)] = KIRExprID(rawValue: 99)
        ctx.currentImplicitReceiverExprID = KIRExprID(rawValue: 7)
        ctx.currentImplicitReceiverSymbol = SymbolID(rawValue: 3)
        ctx.loopControlStack = [(continueLabel: 1, breakLabel: 2, name: nil)]
        ctx.nextLoopLabel = 50000

        ctx.restoreScope(snapshot)

        #expect(ctx.localValuesBySymbol.isEmpty)
        #expect(ctx.currentImplicitReceiverExprID == nil)
        #expect(ctx.currentImplicitReceiverSymbol == nil)
        #expect(ctx.loopControlStack.isEmpty)
        #expect(ctx.nextLoopLabel == 10000)
    }

    @Test func testRestoreScopePreservesSnapshotValues() {
        ctx.localValuesBySymbol[SymbolID(rawValue: 1)] = KIRExprID(rawValue: 42)
        ctx.nextLoopLabel = 15000
        let snapshot = ctx.saveScope()

        ctx.resetScopeForFunction()
        #expect(ctx.localValuesBySymbol.isEmpty)

        ctx.restoreScope(snapshot)
        #expect(ctx.localValuesBySymbol[SymbolID(rawValue: 1)] == KIRExprID(rawValue: 42))
        #expect(ctx.nextLoopLabel == 15000)
    }

    // MARK: - Scope Management: withNewScope

    @Test func testWithNewScopeResetsAndRestoresAfterBlock() {
        ctx.localValuesBySymbol[SymbolID(rawValue: 5)] = KIRExprID(rawValue: 5)
        ctx.nextLoopLabel = 20000

        ctx.withNewScope {
            #expect(ctx.localValuesBySymbol.isEmpty, "Scope inside block should be reset")
            #expect(ctx.nextLoopLabel == 10000, "Label should reset inside block")
            ctx.localValuesBySymbol[SymbolID(rawValue: 9)] = KIRExprID(rawValue: 9)
        }

        #expect(ctx.localValuesBySymbol[SymbolID(rawValue: 5)] == KIRExprID(rawValue: 5),
                       "Original localValues should be restored")
        #expect(ctx.localValuesBySymbol[SymbolID(rawValue: 9)] == nil, "Inner scope changes should not leak")
        #expect(ctx.nextLoopLabel == 20000, "Label should be restored after block")
    }

    @Test func testNestedWithNewScopeRestoresCorrectly() {
        ctx.nextLoopLabel = 30000

        ctx.withNewScope {
            #expect(ctx.nextLoopLabel == 10000)
            ctx.nextLoopLabel = 40000

            ctx.withNewScope {
                #expect(ctx.nextLoopLabel == 10000)
            }

            #expect(ctx.nextLoopLabel == 40000, "Inner withNewScope should restore to outer value")
        }

        #expect(ctx.nextLoopLabel == 30000, "Outer withNewScope should restore to original value")
    }

    @Test func testWithNewScopeRethrowsErrors() throws {
        struct TestError: Error {}
        #expect(throws: (any Error).self) {
            try ctx.withNewScope { throw TestError() }
        }
    }

    // MARK: - Scope Management: resetScopeForFunction

    @Test func testResetScopeForFunctionClearsAllScopeProperties() {
        ctx.localValuesBySymbol[SymbolID(rawValue: 1)] = KIRExprID(rawValue: 1)
        ctx.currentImplicitReceiverExprID = KIRExprID(rawValue: 3)
        ctx.currentImplicitReceiverSymbol = SymbolID(rawValue: 2)
        ctx.loopControlStack = [(continueLabel: 10, breakLabel: 20, name: nil), (continueLabel: 30, breakLabel: 40, name: nil)]
        ctx.nextLoopLabel = 99999

        ctx.resetScopeForFunction()

        #expect(ctx.localValuesBySymbol.isEmpty)
        #expect(ctx.currentImplicitReceiverExprID == nil)
        #expect(ctx.currentImplicitReceiverSymbol == nil)
        #expect(ctx.loopControlStack.isEmpty)
        #expect(ctx.nextLoopLabel == 10000)
    }

    // MARK: - Label Allocation

    @Test func testMakeLoopLabelStartsAt10000() {
        #expect(ctx.makeLoopLabel() == 10000)
    }

    @Test func testMakeLoopLabelIncrements() {
        let first = ctx.makeLoopLabel()
        let second = ctx.makeLoopLabel()
        let third = ctx.makeLoopLabel()
        #expect(first == 10000)
        #expect(second == 10001)
        #expect(third == 10002)
    }

    @Test func testMakeLoopLabelResetsAfterResetScope() {
        _ = ctx.makeLoopLabel()
        _ = ctx.makeLoopLabel()
        #expect(ctx.nextLoopLabel == 10002)

        ctx.resetScopeForFunction()
        #expect(ctx.makeLoopLabel() == 10000)
    }

    @Test func testLabelAllocationInsideWithNewScopeResetsTo10000() {
        _ = ctx.makeLoopLabel()
        _ = ctx.makeLoopLabel()

        var labelInsideScope: Int32 = -1
        ctx.withNewScope {
            labelInsideScope = ctx.makeLoopLabel()
        }

        #expect(labelInsideScope == 10000, "Labels inside withNewScope should start at 10000")
        #expect(ctx.nextLoopLabel == 10002, "Labels should be restored after withNewScope")
    }

    // MARK: - Callable Lowering Scope

    @Test func testBeginCallableLoweringScopeClearsPendingDecls() {
        ctx.pendingGeneratedCallableDeclIDs = [KIRDeclID(rawValue: 1), KIRDeclID(rawValue: 2)]
        ctx.beginCallableLoweringScope()
        #expect(ctx.pendingGeneratedCallableDeclIDs.isEmpty)
    }

    @Test func testDrainGeneratedCallableDeclsReturnsAndClears() {
        ctx.pendingGeneratedCallableDeclIDs = [KIRDeclID(rawValue: 10), KIRDeclID(rawValue: 20)]
        let drained = ctx.drainGeneratedCallableDecls()
        #expect(drained.map(\.rawValue) == [10, 20])
        #expect(ctx.pendingGeneratedCallableDeclIDs.isEmpty)
    }

    @Test func testDrainGeneratedCallableDeclsReturnsEmptyWhenNothingPending() {
        let drained = ctx.drainGeneratedCallableDecls()
        #expect(drained.isEmpty)
    }

    @Test func testRegisterCallableValueStoresInfo() {
        let interner = StringInterner()
        let exprID = KIRExprID(rawValue: 7)
        let symbol = SymbolID(rawValue: 3)
        let callee = interner.intern("myLambda")
        let captureArgs = [KIRExprID(rawValue: 1), KIRExprID(rawValue: 2)]

        ctx.registerCallableValue(exprID, symbol: symbol, callee: callee, captureArguments: captureArgs)

        let info = ctx.callableValueInfoByExprID[exprID]
        #expect(info != nil)
        #expect(info?.symbol == symbol)
        #expect(info?.callee == callee)
        #expect(info?.captureArguments == captureArgs)
    }

    @Test func testRegisterCallableValueOverwritesPrevious() {
        let interner = StringInterner()
        let exprID = KIRExprID(rawValue: 7)
        let callee1 = interner.intern("first")
        let callee2 = interner.intern("second")

        ctx.registerCallableValue(exprID, symbol: SymbolID(rawValue: 1), callee: callee1, captureArguments: [])
        ctx.registerCallableValue(exprID, symbol: SymbolID(rawValue: 2), callee: callee2, captureArguments: [])

        #expect(ctx.callableValueInfoByExprID[exprID]?.callee == callee2)
    }

    // MARK: - Synthetic Symbol Management

    @Test func testSyntheticLambdaSymbolReturnsSameIDForSameExprID() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)

        let exprID = ExprID(rawValue: 1)
        let id1 = ctx.syntheticLambdaSymbol(for: exprID)
        let id2 = ctx.syntheticLambdaSymbol(for: exprID)

        #expect(id1 == id2)
    }

    @Test func testSyntheticLambdaSymbolReturnsDifferentIDsForDifferentExprIDs() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)

        let id1 = ctx.syntheticLambdaSymbol(for: ExprID(rawValue: 1))
        let id2 = ctx.syntheticLambdaSymbol(for: ExprID(rawValue: 2))

        #expect(id1 != id2)
    }

    @Test func testAllocateSyntheticGeneratedSymbolIncrementsSequentially() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)
        let base = ctx.nextSyntheticLambdaSymbolRawValue

        let s1 = ctx.allocateSyntheticGeneratedSymbol()
        let s2 = ctx.allocateSyntheticGeneratedSymbol()

        #expect(s1.rawValue == base)
        #expect(s2.rawValue == base - 1)
    }

    @Test func testInitializeSyntheticLambdaSymbolAllocatorUsesAtLeast1() {
        let semaModule = makeSemaModule().ctx
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)
        #expect(ctx.nextSyntheticLambdaSymbolRawValue <= -60_000_000)
    }

    @Test func testInitializeSyntheticLambdaSymbolAllocatorBasedOnSymbolCount() {
        let (semaModule, symbols, _, interner) = makeSemaModule()
        // Define a symbol so count > 0
        _ = symbols.define(
            kind: .function,
            name: interner.intern("foo"),
            fqName: [interner.intern("foo")],
            declSite: nil,
            visibility: .public
        )
        ctx.initializeSyntheticLambdaSymbolAllocator(sema: semaModule)
        #expect(ctx.nextSyntheticLambdaSymbolRawValue <= -60_000_000)
    }

    // MARK: - Module State Reset

    @Test func testResetModuleStateClearsAllModuleLevelCollections() {
        let interner = StringInterner()
        let exprID = KIRExprID(rawValue: 1)
        ctx.pendingGeneratedCallableDeclIDs = [KIRDeclID(rawValue: 1)]
        ctx.registerCallableValue(exprID, symbol: SymbolID(rawValue: 1), callee: interner.intern("x"), captureArguments: [])
        ctx.syntheticLambdaSymbolsByExprID[ExprID(rawValue: 1)] = SymbolID(rawValue: 1)
        ctx.syntheticObjectLiteralSymbolsByExprID[ExprID(rawValue: 2)] = (
            nominalSymbol: SymbolID(rawValue: 2),
            constructorSymbol: SymbolID(rawValue: 3),
            constructorName: interner.intern("Obj")
        )
        ctx.emittedObjectLiteralExprIDs.insert(ExprID(rawValue: 3))

        ctx.resetModuleState()

        #expect(ctx.pendingGeneratedCallableDeclIDs.isEmpty)
        #expect(ctx.callableValueInfoByExprID.isEmpty)
        #expect(ctx.syntheticLambdaSymbolsByExprID.isEmpty)
        #expect(ctx.syntheticObjectLiteralSymbolsByExprID.isEmpty)
        #expect(ctx.emittedObjectLiteralExprIDs.isEmpty)
    }
}
#endif
