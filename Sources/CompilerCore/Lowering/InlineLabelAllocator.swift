/// Inline expansion numbers labels twice, on purpose, and the two numbering
/// spaces have different jobs:
///
/// - **Scratch.** While an expansion is still being assembled -- an inline
///   body plus any lambda bodies spliced into it -- every label it creates
///   (branch targets copied from the callee, the merge label a multi-`return`
///   body needs) takes a scratch ID. Those only have to be unique across the
///   one expansion being built, because `relocate(_:)` renumbers all of them
///   before the expansion reaches the caller, so no scratch ID is ever
///   observable in the result.
/// - **Caller.** `relocate(_:)`, the throw-dispatch label and the
///   non-local-return exit label take IDs from the caller cursor, which starts
///   above every label the caller body already references -- whether emitted
///   by `ControlFlowLowerer` (10000 base), `TailrecLoweringPass` (9000 base,
///   and it runs before this pass) or by an earlier expansion round.
///
/// Routing *everything* that lands in the caller through the one cursor is
/// what makes collisions impossible, so it is the invariant to preserve:
/// appending an expansion without `relocate(_:)` leaks scratch IDs into the
/// caller body, where they can alias a label the caller cursor already handed
/// out (or one a later `relocate(_:)` is about to reuse).
struct InlineLabelAllocator {
    /// The maximum label ID permitted from untrusted inputs (e.g. imported KIR artifacts).
    /// Leaves ample room (over 1 billion IDs) below `Int32.max` for expansion and relocation cursors.
    static let maxSupportedLabel: Int32 = 1_000_000_000

    /// Floor for scratch IDs. It preserves the numbering this pass used before
    /// the allocator was extracted, and keeps a scratch ID from colliding with
    /// a label the callee body references but never defines -- malformed KIR
    /// that `relocate(_:)` would otherwise carry through unremapped. It is not
    /// what keeps scratch IDs clear of `TailrecLoweringPass`'s own 9000 base:
    /// that pass runs first, so its labels are in `callerBody` and the scan
    /// below already covers them.
    private static let scratchFloor: Int32 = 9000

    private(set) var hasOverflowed: Bool = false
    private var nextScratchLabel: Int32
    private var nextCallerLabel: Int32

    init(callerBody: some Sequence<KIRInstruction>) {
        var highestDefined: Int32 = Self.scratchFloor - 1
        var highestReferenced: Int32 = -1
        for instruction in callerBody {
            if case let .label(id) = instruction {
                highestDefined = max(highestDefined, id)
            }
            if let id = KIRLabelRelocation.maxLabelID(of: instruction) {
                highestReferenced = max(highestReferenced, id)
            }
        }
        if highestDefined == Int32.max || highestReferenced == Int32.max {
            hasOverflowed = true
            nextScratchLabel = Int32.max
            nextCallerLabel = Int32.max
        } else {
            nextScratchLabel = highestDefined + 1
            nextCallerLabel = highestReferenced + 1
        }
    }

    mutating func allocateScratchLabel() -> Int32 {
        if nextScratchLabel == Int32.max {
            hasOverflowed = true
            return Int32.max
        }
        defer { nextScratchLabel += 1 }
        return nextScratchLabel
    }

    mutating func allocateCallerLabel() -> Int32 {
        if nextCallerLabel == Int32.max {
            hasOverflowed = true
            return Int32.max
        }
        defer { nextCallerLabel += 1 }
        return nextCallerLabel
    }

    mutating func relocate(_ instructions: [KIRInstruction]) -> [KIRInstruction] {
        var labelMapping: [Int32: Int32] = [:]
        return relocate(instructions, labelMapping: &labelMapping)
    }

    mutating func relocate(
        _ instructions: [KIRInstruction], labelMapping: inout [Int32: Int32]
    ) -> [KIRInstruction] {
        var labelIDs: Set<Int32> = []
        let locallyDefinedLabels = Set(instructions.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction { return id }
            return nil
        })
        for instruction in instructions {
            if let id = KIRLabelRelocation.maxLabelID(of: instruction) {
                labelIDs.insert(id)
            }
            if case let .jump(target) = instruction,
               let externalTarget = KIRExternalLoopJump.label(for: target),
               locallyDefinedLabels.contains(externalTarget)
            {
                labelIDs.insert(externalTarget)
            }
        }
        guard !labelIDs.isEmpty else {
            labelMapping = [:]
            return instructions
        }

        var mapping: [Int32: Int32] = [:]
        for id in labelIDs.sorted() {
            mapping[id] = allocateCallerLabel()
        }
        labelMapping = mapping
        return instructions.map { KIRLabelRelocation.rewriteLabels(of: $0, mapping: mapping) }
    }
}
