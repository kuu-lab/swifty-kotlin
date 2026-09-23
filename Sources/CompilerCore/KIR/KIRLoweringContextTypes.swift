
struct KIRLoweringSharedContext {
    let ast: ASTModule
    let sema: SemaModule
    let arena: KIRArena
    let interner: StringInterner
    let propertyConstantInitializers: [SymbolID: KIRExprKind]
}

struct KIRLoweringEmitContext: RandomAccessCollection, MutableCollection, RangeReplaceableCollection, ExpressibleByArrayLiteral {
    typealias Element = KIRInstruction
    typealias Index = Array<KIRInstruction>.Index

    var instructions: [KIRInstruction]
    /// Per-instruction source locations, parallel to ``instructions``.
    /// `nil` entries mean "same as function-level location".
    var instructionLocations: [SourceRange?]
    /// The current source range to associate with newly appended instructions.
    /// Set this before appending instructions to propagate source locations.
    var currentSourceRange: SourceRange?
    /// Highest label ID among the instructions accumulated so far. Kept in
    /// sync by the collection mutators below so ``appendRelocatingLabels``
    /// can read it in O(1) instead of rescanning the whole buffer per splice.
    ///
    /// Only mutations through the collection interface update it — writes
    /// that reach `instructions` directly (e.g. `&context.instructions`)
    /// bypass the bookkeeping, so a context mutated that way must not be
    /// used as the relocation target.
    private(set) var maxLabelID: Int32?

    init(_ instructions: [KIRInstruction] = []) {
        self.instructions = instructions
        instructionLocations = Array(repeating: nil, count: instructions.count)
        currentSourceRange = nil
        maxLabelID = KIRLabelRelocation.maxLabelID(in: instructions)
    }

    init() {
        instructions = []
        instructionLocations = []
        currentSourceRange = nil
        maxLabelID = nil
    }

    init(arrayLiteral elements: KIRInstruction...) {
        instructions = elements
        instructionLocations = Array(repeating: nil, count: elements.count)
        currentSourceRange = nil
        maxLabelID = KIRLabelRelocation.maxLabelID(in: elements)
    }

    var startIndex: Index {
        instructions.startIndex
    }

    var endIndex: Index {
        instructions.endIndex
    }

    func index(after i: Index) -> Index {
        instructions.index(after: i)
    }

    func index(before i: Index) -> Index {
        instructions.index(before: i)
    }

    subscript(position: Index) -> KIRInstruction {
        get { instructions[position] }
        set {
            let removedMaxLabelID = KIRLabelRelocation.labelIDs(of: instructions[position]).max()
            let insertedMaxLabelID = KIRLabelRelocation.labelIDs(of: newValue).max()
            instructions[position] = newValue
            noteReplacedLabels(removedMax: removedMaxLabelID, insertedMax: insertedMaxLabelID)
        }
    }

    mutating func replaceSubrange<C: Collection>(_ subrange: Range<Index>, with newElements: C) where KIRInstruction == C.Element {
        let removedMaxLabelID = KIRLabelRelocation.maxLabelID(in: instructions[subrange])
        let insertedMaxLabelID = KIRLabelRelocation.maxLabelID(in: newElements)
        instructions.replaceSubrange(subrange, with: newElements)
        // Keep instructionLocations in sync with the same structural edit.
        if instructionLocations.count < subrange.upperBound {
            instructionLocations.append(
                contentsOf: repeatElement(nil, count: subrange.upperBound - instructionLocations.count)
            )
        }
        let newLocations = Array(repeating: currentSourceRange, count: newElements.count)
        instructionLocations.replaceSubrange(subrange, with: newLocations)
        // Final safety sync.
        if instructionLocations.count < instructions.count {
            instructionLocations.append(
                contentsOf: repeatElement(nil, count: instructions.count - instructionLocations.count)
            )
        } else if instructionLocations.count > instructions.count {
            instructionLocations.removeLast(instructionLocations.count - instructions.count)
        }
        noteReplacedLabels(removedMax: removedMaxLabelID, insertedMax: insertedMaxLabelID)
    }

    /// Reconciles ``maxLabelID`` after a structural edit. The full buffer is
    /// rescanned only when the edit removed the instruction(s) supplying the
    /// current maximum without inserting an equal-or-higher ID, so appends
    /// stay O(1) in the tracked value.
    private mutating func noteReplacedLabels(removedMax: Int32?, insertedMax: Int32?) {
        guard let current = maxLabelID else {
            maxLabelID = insertedMax
            return
        }
        if removedMax == current, (insertedMax ?? .min) < current {
            maxLabelID = KIRLabelRelocation.maxLabelID(in: instructions)
        } else if let insertedMax {
            maxLabelID = Swift.max(current, insertedMax)
        }
    }
}

extension KIRFunction {
    init(
        symbol: SymbolID,
        name: InternedString,
        params: [KIRParameter],
        returnType: TypeID,
        body: KIRLoweringEmitContext,
        isSuspend: Bool,
        isInline: Bool,
        isTailrec: Bool = false,
        sourceRange: SourceRange? = nil
    ) {
        self.init(
            symbol: symbol,
            name: name,
            params: params,
            returnType: returnType,
            body: body.instructions,
            isSuspend: isSuspend,
            isInline: isInline,
            isTailrec: isTailrec,
            sourceRange: sourceRange,
            instructionLocations: body.instructionLocations
        )
    }

    mutating func replaceBody(_ emit: KIRLoweringEmitContext) {
        replaceBody(emit.instructions, locations: emit.instructionLocations)
    }
}
