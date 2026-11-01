
/// Negative jump targets temporarily represent loops outside a lambda's KIR
/// function. Inline expansion rewrites their IDs when the target loop belongs
/// to an enclosing lambda body, then resolves them once the loop is in scope.
enum KIRExternalLoopJump {
    static func marker(for label: Int32) -> Int32 { -label }

    static func label(for marker: Int32) -> Int32? {
        marker < 0 ? -marker : nil
    }

    static func containsExternalJump(in instructions: [KIRInstruction]) -> Bool {
        instructions.contains { instruction in
            guard case let .jump(target) = instruction else { return false }
            return label(for: target) != nil
        }
    }

    static func resolvingTargets(in instructions: [KIRInstruction]) -> [KIRInstruction] {
        let definedLabels = Set(instructions.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction { return id }
            return nil
        })
        return instructions.map { instruction in
            guard case let .jump(marker) = instruction,
                  let target = label(for: marker),
                  definedLabels.contains(target)
            else { return instruction }
            return .jump(target)
        }
    }

    static func remappingTargets(
        in instructions: [KIRInstruction], mapping: [Int32: Int32]
    ) -> [KIRInstruction] {
        instructions.map { instruction in
            guard case let .jump(marker) = instruction,
                  let externalTarget = label(for: marker),
                  let remappedTarget = mapping[externalTarget]
            else { return instruction }
            return .jump(Self.marker(for: remappedTarget))
        }
    }
}

/// `KIRLoweringContext.makeLoopLabel` restarts at 10000 for every function
/// scope, which is safe as long as each lowered stream becomes its own
/// function.  Top-level property initializers break that assumption: each one
/// is lowered under a fresh scope and then all of them are spliced into
/// `main` (see `KIRLoweringDriver.postProcessTopLevelInitializersAndDelegates`).
/// Without relocation, two branching initializers (`val a = if (...) ... `)
/// both define `L10000`, the code generator folds them into one basic block,
/// and the resulting module is malformed IR that crashes LLVM.
enum KIRLabelRelocation {
    static func relocatingLabels(
        of instructions: [KIRInstruction],
        toAvoidCollisionsWith existing: some Sequence<KIRInstruction>
    ) -> [KIRInstruction] {
        relocatingLabels(of: instructions, existingMaxLabelID: maxLabelID(in: existing))
    }

    /// Callers that accumulate a stream incrementally — `KIRLoweringEmitContext`
    /// tracks ``maxLabelID`` — pass the tracked value here so each append costs
    /// O(instructions) instead of rescanning the whole accumulated buffer.
    static func relocatingLabels(
        of instructions: [KIRInstruction],
        existingMaxLabelID: Int32?
    ) -> [KIRInstruction] {
        var labelIDs: Set<Int32> = []
        let locallyDefinedLabels = Set(instructions.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction { return id }
            return nil
        })
        for instruction in instructions {
            if let id = Self.maxLabelID(of: instruction) {
                labelIDs.insert(id)
            }
            if case let .jump(target) = instruction,
               let externalTarget = KIRExternalLoopJump.label(for: target),
               locallyDefinedLabels.contains(externalTarget)
            {
                labelIDs.insert(externalTarget)
            }
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
            if let labelID = maxLabelID(of: instruction), labelID > (highest ?? Int32.min) {
                highest = labelID
            }
        }
        return highest
    }

    /// Single-instruction form of `maxLabelID(in:)`: every label-carrying
    /// case yields at most one ID, so the answer needs no array allocation —
    /// emit-heavy paths call this per appended instruction (KUU-3777).
    static func maxLabelID(of instruction: KIRInstruction) -> Int32? {
        switch instruction {
        case let .label(id):
            return id
        case let .jump(target):
            return KIRExternalLoopJump.label(for: target) == nil ? target : nil
        case let .jumpIfEqual(_, _, target):
            return target
        case let .jumpIfNotNull(_, target):
            return target
        case let .beginNonLocalReturnScope(_, target, _):
            return target
        default:
            return nil
        }
    }

    /// The single place that enumerates the label-carrying instruction cases,
    /// so a new one cannot be relocated by one caller and missed by another.
    static func labelIDs(of instruction: KIRInstruction) -> [Int32] {
        switch instruction {
        case let .label(id):
            return [id]
        case let .jump(target):
            return KIRExternalLoopJump.label(for: target) == nil ? [target] : []
        case let .jumpIfEqual(_, _, target):
            return [target]
        case let .jumpIfNotNull(_, target):
            return [target]
        case let .beginNonLocalReturnScope(_, target, _):
            return [target]
        default:
            return []
        }
    }

    static func rewriteLabels(
        of instruction: KIRInstruction,
        mapping: [Int32: Int32]
    ) -> KIRInstruction {
        switch instruction {
        case let .label(id):
            return .label(mapping[id] ?? id)
        case let .jump(target):
            if let externalTarget = KIRExternalLoopJump.label(for: target) {
                return .jump(KIRExternalLoopJump.marker(for: mapping[externalTarget] ?? externalTarget))
            }
            return .jump(mapping[target] ?? target)
        case let .jumpIfEqual(lhs, rhs, target):
            return .jumpIfEqual(lhs: lhs, rhs: rhs, target: mapping[target] ?? target)
        case let .jumpIfNotNull(value, target):
            return .jumpIfNotNull(value: value, target: mapping[target] ?? target)
        case let .beginNonLocalReturnScope(value, target, function):
            return .beginNonLocalReturnScope(value: value, target: mapping[target] ?? target, function: function)
        default:
            return instruction
        }
    }
}

extension KIRLoweringEmitContext {
    mutating func appendRelocatingLabels(contentsOf other: KIRLoweringEmitContext) {
        append(contentsOf: KIRLabelRelocation.relocatingLabels(
            of: other.instructions,
            existingMaxLabelID: maxLabelID
        ))
    }
}
