/// Owns every control-flow label ID that inline expansion introduces into one
/// caller function body, and moves finished expansions into that body's label
/// namespace.
///
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
    /// Floor for scratch IDs. It preserves the numbering this pass used before
    /// the allocator was extracted, and keeps a scratch ID from colliding with
    /// a label the callee body references but never defines -- malformed KIR
    /// that `relocate(_:)` would otherwise carry through unremapped. It is not
    /// what keeps scratch IDs clear of `TailrecLoweringPass`'s own 9000 base:
    /// that pass runs first, so its labels are in `callerBody` and the scan
    /// below already covers them.
    private static let scratchFloor: Int32 = 9000

    private var nextScratchLabel: Int32
    private var nextCallerLabel: Int32

    /// Starts both cursors above the labels `callerBody` already uses.
    init(callerBody: some Sequence<KIRInstruction>) {
        var highestDefined: Int32 = Self.scratchFloor - 1
        var highestReferenced: Int32 = -1
        for instruction in callerBody {
            if case let .label(id) = instruction {
                highestDefined = max(highestDefined, id)
            }
            for id in KIRLabelRelocation.labelIDs(of: instruction) {
                highestReferenced = max(highestReferenced, id)
            }
        }
        nextScratchLabel = highestDefined + 1
        nextCallerLabel = highestReferenced + 1
    }

    /// A label ID for a merge or exit point inside an expansion that is still
    /// being assembled. `relocate(_:)` renumbers it on the way out.
    mutating func allocateScratchLabel() -> Int32 {
        defer { nextScratchLabel += 1 }
        return nextScratchLabel
    }

    /// A label ID emitted straight into the caller body (the throw-dispatch
    /// label, the non-local-return exit label).
    mutating func allocateCallerLabel() -> Int32 {
        defer { nextCallerLabel += 1 }
        return nextCallerLabel
    }

    /// Returns `instructions` with every label definition and jump target
    /// renumbered into the caller's namespace, preserving their relative
    /// order. Instructions carrying no label are returned as they are.
    mutating func relocate(_ instructions: [KIRInstruction]) -> [KIRInstruction] {
        var labelIDs: Set<Int32> = []
        for instruction in instructions {
            labelIDs.formUnion(KIRLabelRelocation.labelIDs(of: instruction))
        }
        guard !labelIDs.isEmpty else { return instructions }

        var mapping: [Int32: Int32] = [:]
        for id in labelIDs.sorted() {
            mapping[id] = allocateCallerLabel()
        }
        return instructions.map { KIRLabelRelocation.rewriteLabels(of: $0, mapping: mapping) }
    }
}
