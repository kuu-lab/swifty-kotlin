#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineThrowReroutingTests {
    private let interner = StringInterner()
    private let callerSlot = KIRExprID(rawValue: 100)
    private let localSlot = KIRExprID(rawValue: 200)

    private func makeCall(thrownResult: KIRExprID? = nil) -> KIRInstruction {
        .call(
            symbol: SymbolID(rawValue: 10),
            callee: interner.intern("callee"),
            arguments: [KIRExprID(rawValue: 1)],
            result: KIRExprID(rawValue: 2),
            canThrow: false,
            thrownResult: thrownResult,
            isSuperCall: true,
            qualifiedSuperType: SymbolID(rawValue: 11)
        )
    }

    @Test
    func testUnprotectedCallSitePassesThroughWithoutAllocatingALabel() {
        let body: [KIRInstruction] = [makeCall(), .rethrow(value: KIRExprID(rawValue: 3))]
        var labels = InlineLabelAllocator(callerBody: [KIRInstruction.label(10000)])

        let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: body,
            callerThrownResult: nil,
            labels: &labels
        )

        #expect(reroutedInstructions == body)
        #expect(throwDispatchLabel == nil)
        // No label may be consumed for an unprotected call site.
        #expect(labels.allocateCallerLabel() == 10001)
    }

    @Test
    func testUnprotectedCallIsRoutedToTheCallerSlotAndDispatchLabel() {
        var labels = InlineLabelAllocator(callerBody: [KIRInstruction.label(10000)])

        let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: [makeCall()],
            callerThrownResult: callerSlot,
            labels: &labels
        )

        #expect(throwDispatchLabel == 10001)
        guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType) = reroutedInstructions.first else {
            Issue.record("Expected .call")
            return
        }
        #expect(symbol == SymbolID(rawValue: 10))
        #expect(callee == interner.intern("callee"))
        #expect(arguments == [KIRExprID(rawValue: 1)])
        #expect(result == KIRExprID(rawValue: 2))
        #expect(canThrow)
        #expect(thrownResult == callerSlot)
        #expect(isSuperCall)
        #expect(qualifiedSuperType == SymbolID(rawValue: 11))
        #expect(reroutedInstructions.last == .jumpIfNotNull(value: callerSlot, target: 10001))
        #expect(reroutedInstructions.count == 2)
    }

    @Test
    func testUnprotectedVirtualCallIsRoutedKeepingReceiverAndDispatch() {
        let dispatch = KIRDispatchKind.itableDynamic(interfaceTypeID: 77, methodSlot: 2)
        let call = KIRInstruction.virtualCall(
            symbol: SymbolID(rawValue: 10),
            callee: interner.intern("virtualCallee"),
            receiver: KIRExprID(rawValue: 1),
            arguments: [KIRExprID(rawValue: 3)],
            result: KIRExprID(rawValue: 4),
            canThrow: false,
            thrownResult: nil,
            dispatch: dispatch
        )
        var labels = InlineLabelAllocator(callerBody: [KIRInstruction]())

        let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: [call],
            callerThrownResult: callerSlot,
            labels: &labels
        )

        guard let throwDispatchLabel else {
            Issue.record("Expected a dispatch label")
            return
        }
        #expect(reroutedInstructions == [
            .virtualCall(
                symbol: SymbolID(rawValue: 10),
                callee: interner.intern("virtualCallee"),
                receiver: KIRExprID(rawValue: 1),
                arguments: [KIRExprID(rawValue: 3)],
                result: KIRExprID(rawValue: 4),
                canThrow: true,
                thrownResult: callerSlot,
                dispatch: dispatch
            ),
            .jumpIfNotNull(value: callerSlot, target: throwDispatchLabel),
        ])
    }

    @Test
    func testRethrowBecomesCopyIntoCallerSlotPlusJump() {
        let thrown = KIRExprID(rawValue: 5)
        var labels = InlineLabelAllocator(callerBody: [KIRInstruction]())

        let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: [.rethrow(value: thrown)],
            callerThrownResult: callerSlot,
            labels: &labels
        )

        guard let throwDispatchLabel else {
            Issue.record("Expected a dispatch label")
            return
        }
        #expect(reroutedInstructions == [
            .copy(from: thrown, to: callerSlot),
            .jump(throwDispatchLabel),
        ])
    }

    @Test
    func testAlreadyLocallyRoutedCallsAreNotRewrittenASecondTime() {
        // The callee's own try/catch already claims this call's throw; routing
        // it to the caller slot as well would steal it from the local handler.
        let body: [KIRInstruction] = [makeCall(thrownResult: localSlot)]
        var labels = InlineLabelAllocator(callerBody: [KIRInstruction]())

        let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: body,
            callerThrownResult: callerSlot,
            labels: &labels
        )

        #expect(reroutedInstructions == body)
        // The dispatch label is still allocated eagerly so numbering does not
        // depend on the expansion's contents.
        #expect(throwDispatchLabel != nil)
    }

    @Test
    func testFinallyGuardRegionsPassThroughUntouched() {
        // Throws inside a guard region are already claimed by the guard's own
        // dispatch, at any nesting depth.
        let body: [KIRInstruction] = [
            .beginFinallyGuard,
            .beginFinallyGuard,
            makeCall(),
            .rethrow(value: KIRExprID(rawValue: 5)),
            .endFinallyGuard,
            makeCall(),
            .endFinallyGuard,
            makeCall(),
        ]
        var labels = InlineLabelAllocator(callerBody: [KIRInstruction]())

        let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: body,
            callerThrownResult: callerSlot,
            labels: &labels
        )

        guard let throwDispatchLabel else {
            Issue.record("Expected a dispatch label")
            return
        }
        var expected = body
        // Only the trailing unguarded call is rerouted; the call between the
        // first `.endFinallyGuard` and the final `.endFinallyGuard` still sits
        // inside the outer guard.
        expected[7] = .call(
            symbol: SymbolID(rawValue: 10),
            callee: interner.intern("callee"),
            arguments: [KIRExprID(rawValue: 1)],
            result: KIRExprID(rawValue: 2),
            canThrow: true,
            thrownResult: callerSlot,
            isSuperCall: true,
            qualifiedSuperType: SymbolID(rawValue: 11)
        )
        #expect(reroutedInstructions == expected + [.jumpIfNotNull(value: callerSlot, target: throwDispatchLabel)])
    }

    @Test
    func testDispatchLabelComesFromTheCallerNamespace() {
        // The label must sit above every label the caller already references,
        // sharing the cursor with the expansion's relocated labels and the
        // non-local-return exit label.
        var labels = InlineLabelAllocator(callerBody: [
            .label(10000),
            .jump(10007),
        ])

        let (_, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: [makeCall()],
            callerThrownResult: callerSlot,
            labels: &labels
        )

        #expect(throwDispatchLabel == 10008)
        #expect(labels.allocateCallerLabel() == 10009)
    }
}
#endif
