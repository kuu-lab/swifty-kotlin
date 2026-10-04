
/// Rewrites control-flow label IDs so that instruction streams lowered
/// independently can be concatenated into a single function body.
///
/// `KIRLoweringContext.makeLoopLabel` restarts at 10000 for every function
/// scope, which is safe as long as each lowered stream becomes its own
/// function.  Top-level property initializers break that assumption: each one
/// is lowered under a fresh scope and then all of them are spliced into
/// `main` (see `KIRLoweringDriver.postProcessTopLevelInitializersAndDelegates`).
/// Without relocation, two branching initializers (`val a = if (...) ... `)
/// both define `L10000`, the code generator folds them into one basic block,
/// and the resulting module is malformed IR that crashes LLVM.
enum KIRLabelRelocation {
    /// Returns `instructions` with every label ID rewritten to a fresh ID
    /// above all labels used by `existing`.  Returns them unchanged when the
    /// two streams already use disjoint label ranges.
    static func relocatingLabels(
        of instructions: [KIRInstruction],
        toAvoidCollisionsWith existing: some Sequence<KIRInstruction>
    ) -> [KIRInstruction] {
        relocatingLabels(of: instructions, existingMaxLabelID: maxLabelID(in: existing))
    }

    /// Same relocation as ``relocatingLabels(of:toAvoidCollisionsWith:)``,
    /// but takes the highest label ID the destination stream already uses
    /// (`nil` when it carries none). Callers that accumulate a stream
    /// incrementally — `KIRLoweringEmitContext` tracks ``maxLabelID`` — pass
    /// the tracked value here so each append costs O(instructions) instead
    /// of rescanning the whole accumulated buffer.
    static func relocatingLabels(
        of instructions: [KIRInstruction],
        existingMaxLabelID: Int32?
    ) -> [KIRInstruction] {
        var labelIDs: Set<Int32> = []
        for instruction in instructions {
            labelIDs.formUnion(Self.labelIDs(of: instruction))
        }
        guard let lowestLabelID = labelIDs.min(),
              let existingMaxLabelID,
              lowestLabelID <= existingMaxLabelID
        else { return instructions }

        var mapping: [Int32: Int32] = [:]
        var nextLabelID = existingMaxLabelID + 1
        for labelID in labelIDs.sorted() {
            mapping[labelID] = nextLabelID
            nextLabelID += 1
        }
        return instructions.map { rewriteLabels(of: $0, mapping: mapping) }
    }

    static func maxLabelID(in instructions: some Sequence<KIRInstruction>) -> Int32? {
        var highest: Int32?
        for instruction in instructions {
            for labelID in labelIDs(of: instruction) where labelID > (highest ?? Int32.min) {
                highest = labelID
            }
        }
        return highest
    }

    /// Every label ID `instruction` defines or references. The single place
    /// that enumerates the label-carrying instruction cases, so a new one
    /// cannot be relocated by one caller and missed by another.
    static func labelIDs(of instruction: KIRInstruction) -> [Int32] {
        switch instruction {
        case let .label(id):
            return [id]
        case let .jump(target):
            return [target]
        case let .jumpIfEqual(_, _, target):
            return [target]
        case let .jumpIfNotNull(_, target):
            return [target]
        default:
            return []
        }
    }

    /// Applies `mapping` to every label ID in `instruction`, leaving IDs the
    /// mapping does not mention untouched.
    static func rewriteLabels(
        of instruction: KIRInstruction,
        mapping: [Int32: Int32]
    ) -> KIRInstruction {
        switch instruction {
        case let .label(id):
            return .label(mapping[id] ?? id)
        case let .jump(target):
            return .jump(mapping[target] ?? target)
        case let .jumpIfEqual(lhs, rhs, target):
            return .jumpIfEqual(lhs: lhs, rhs: rhs, target: mapping[target] ?? target)
        case let .jumpIfNotNull(value, target):
            return .jumpIfNotNull(value: value, target: mapping[target] ?? target)
        default:
            return instruction
        }
    }
}

extension KIRLoweringEmitContext {
    /// Appends an independently lowered instruction stream, relocating its
    /// labels above the ones already accumulated here.
    mutating func appendRelocatingLabels(contentsOf other: KIRLoweringEmitContext) {
        append(contentsOf: KIRLabelRelocation.relocatingLabels(
            of: other.instructions,
            existingMaxLabelID: maxLabelID
        ))
    }
}
