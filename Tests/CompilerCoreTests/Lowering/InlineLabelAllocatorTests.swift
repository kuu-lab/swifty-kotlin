#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineLabelAllocatorTests {
    private func labelIDs(of instructions: [KIRInstruction]) -> [Int32] {
        instructions.flatMap { KIRLabelRelocation.labelIDs(of: $0) }
    }

    @Test
    func testCallerLabelsStartAboveEveryLabelTheCallerAlreadyReferences() {
        // The highest ID sits on a jump whose label is never defined in this
        // slice, so scanning only `.label` would hand it out again.
        var allocator = InlineLabelAllocator(callerBody: [
            .label(10000),
            .jump(10007),
            .returnUnit,
        ])
        #expect(allocator.allocateCallerLabel() == 10008)
        #expect(allocator.allocateCallerLabel() == 10009)
    }

    @Test
    func testCallerLabelsStartAtZeroForABodyWithoutLabels() {
        var allocator = InlineLabelAllocator(callerBody: [KIRInstruction.returnUnit])
        #expect(allocator.allocateCallerLabel() == 0)
    }

    @Test
    func testScratchLabelsStayAboveTheFloorAndTheCallersLabels() {
        var lowLabels = InlineLabelAllocator(callerBody: [KIRInstruction.label(10)])
        #expect(lowLabels.allocateScratchLabel() == 9000)

        var highLabels = InlineLabelAllocator(callerBody: [KIRInstruction.label(12000)])
        #expect(highLabels.allocateScratchLabel() == 12001)
    }

    @Test
    func testRelocateRewritesDefinitionsAndAllThreeJumpKinds() {
        let arena = KIRArena()
        let types = TypeSystem()
        let lhs = arena.appendExpr(.intLiteral(1), type: types.intType)
        let rhs = arena.appendExpr(.intLiteral(2), type: types.intType)
        let value = arena.appendTemporary(type: types.intType)

        var allocator = InlineLabelAllocator(callerBody: [KIRInstruction.label(10000)])
        let relocated = allocator.relocate([
            .jumpIfEqual(lhs: lhs, rhs: rhs, target: 9001),
            .jumpIfNotNull(value: value, target: 9002),
            .label(9000),
            .jump(9002),
            .label(9001),
            .label(9002),
        ])

        // Sorted source IDs 9000/9001/9002 take consecutive caller IDs, so the
        // stream's branching structure is unchanged.
        #expect(relocated == [
            .jumpIfEqual(lhs: lhs, rhs: rhs, target: 10002),
            .jumpIfNotNull(value: value, target: 10003),
            .label(10001),
            .jump(10003),
            .label(10002),
            .label(10003),
        ])
        #expect(allocator.allocateCallerLabel() == 10004)
    }

    @Test
    func testRelocateLeavesLabelFreeInstructionsAndEmptyStreamsAlone() {
        var allocator = InlineLabelAllocator(callerBody: [KIRInstruction.label(10000)])
        let instructions: [KIRInstruction] = [.nop, .returnUnit]
        #expect(allocator.relocate(instructions) == instructions)
        #expect(allocator.relocate([]) == [])
        // Neither call may consume an ID.
        #expect(allocator.allocateCallerLabel() == 10001)
    }

    @Test
    func testRelocatedExpansionsNeverShareALabelWithEachOtherOrTheCaller() {
        let callerBody: [KIRInstruction] = [.label(10000), .jump(10001), .label(10001)]
        var allocator = InlineLabelAllocator(callerBody: callerBody)

        // Two expansions built from the same callee body, plus the exit label
        // a non-local return needs between them.
        let calleeBody: [KIRInstruction] = [.jump(9000), .label(9000)]
        let first = allocator.relocate(calleeBody)
        let exitLabel = allocator.allocateCallerLabel()
        let second = allocator.relocate(calleeBody)

        let all = labelIDs(of: callerBody) + labelIDs(of: first) + [exitLabel] + labelIDs(of: second)
        let defined = (callerBody + first + second).compactMap { instruction -> Int32? in
            guard case let .label(id) = instruction else { return nil }
            return id
        } + [exitLabel]
        #expect(Set(defined).count == defined.count)
        #expect(Set(all).isSubset(of: Set(defined)))
    }
}
#endif
