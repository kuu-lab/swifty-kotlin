extension CollectionLiteralLoweringSupport {
    enum ClassificationAxis: Sendable, CaseIterable {
        case staticType
        case runtimeRepresentation
    }

    /// `rawValue` doubles as the bit position in ``ClassificationFacts``, so the
    /// cases must stay contiguous from zero.
    enum Classification: Int, CaseIterable, Sendable {
        case list
        case set
        case map
        case array
        case sequence
        case sequenceSourceObject
        case range
        case charRange
        case ulongRange
        case string
        case file
        case path
        case listIterator
        case mapIterator
        case iteratorBuilder
        case ulongRangeIterator
        case sequenceType

        var axis: ClassificationAxis {
            switch self {
            case .list, .set, .map, .array, .sequenceType, .range, .charRange,
                 .ulongRange, .string, .file, .path:
                .staticType
            case .sequence, .sequenceSourceObject,
                 .listIterator, .mapIterator, .iteratorBuilder,
                 .ulongRangeIterator:
                .runtimeRepresentation
            }
        }

        init(_ trackedStaticType: CollectionLiteralTrackedStaticTypeKind) {
            switch trackedStaticType {
            case .list: self = .list
            case .set: self = .set
            case .map: self = .map
            case .array: self = .array
            case .sequence: self = .sequenceType
            case .string: self = .string
            }
        }
    }

    enum SequenceRuntimeRepresentation: Equatable, Sendable {
        case runtimeBox
        case sourceObject
        case notSequence
        case unknown
    }

    struct ClassificationFacts: OptionSet, Sendable {
        var rawValue: UInt32

        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        init(_ classification: Classification) {
            rawValue = 1 << UInt32(classification.rawValue)
        }

        private init(axis: ClassificationAxis) {
            rawValue = Classification.allCases.reduce(into: UInt32(0)) { mask, classification in
                guard classification.axis == axis else { return }
                mask |= 1 << UInt32(classification.rawValue)
            }
        }

        static let staticType = ClassificationFacts(axis: .staticType)
        static let runtimeRepresentation = ClassificationFacts(axis: .runtimeRepresentation)

        static func mask(for axis: ClassificationAxis) -> ClassificationFacts {
            switch axis {
            case .staticType: .staticType
            case .runtimeRepresentation: .runtimeRepresentation
            }
        }

        func contains(_ classification: Classification) -> Bool {
            contains(ClassificationFacts(classification))
        }

        func facts(on axis: ClassificationAxis) -> ClassificationFacts {
            intersection(.mask(for: axis))
        }

        func isUnknown(on axis: ClassificationAxis) -> Bool {
            facts(on: axis).isEmpty
        }

        var classifications: [Classification] {
            Classification.allCases.filter { contains($0) }
        }
    }

    struct CollectionRewriteState {
        private var memberships = Array(
            repeating: Set<Int32>(),
            count: Classification.allCases.count
        )

        var listExprIDs: Set<Int32> {
            get { memberships[Classification.list.rawValue] }
            set { memberships[Classification.list.rawValue] = newValue }
            _modify { yield &memberships[Classification.list.rawValue] }
        }

        var setExprIDs: Set<Int32> {
            get { memberships[Classification.set.rawValue] }
            set { memberships[Classification.set.rawValue] = newValue }
            _modify { yield &memberships[Classification.set.rawValue] }
        }

        var mapExprIDs: Set<Int32> {
            get { memberships[Classification.map.rawValue] }
            set { memberships[Classification.map.rawValue] = newValue }
            _modify { yield &memberships[Classification.map.rawValue] }
        }

        var arrayExprIDs: Set<Int32> {
            get { memberships[Classification.array.rawValue] }
            set { memberships[Classification.array.rawValue] = newValue }
            _modify { yield &memberships[Classification.array.rawValue] }
        }

        var sequenceExprIDs: Set<Int32> {
            get { memberships[Classification.sequence.rawValue] }
            set { memberships[Classification.sequence.rawValue] = newValue }
            _modify { yield &memberships[Classification.sequence.rawValue] }
        }

        var sequenceSourceObjectExprIDs: Set<Int32> {
            get { memberships[Classification.sequenceSourceObject.rawValue] }
            set { memberships[Classification.sequenceSourceObject.rawValue] = newValue }
            _modify { yield &memberships[Classification.sequenceSourceObject.rawValue] }
        }

        var sequenceTypeExprIDs: Set<Int32> {
            get { memberships[Classification.sequenceType.rawValue] }
            set { memberships[Classification.sequenceType.rawValue] = newValue }
            _modify { yield &memberships[Classification.sequenceType.rawValue] }
        }

        var rangeExprIDs: Set<Int32> {
            get { memberships[Classification.range.rawValue] }
            set { memberships[Classification.range.rawValue] = newValue }
            _modify { yield &memberships[Classification.range.rawValue] }
        }

        var charRangeExprIDs: Set<Int32> {
            get { memberships[Classification.charRange.rawValue] }
            set { memberships[Classification.charRange.rawValue] = newValue }
            _modify { yield &memberships[Classification.charRange.rawValue] }
        }

        var ulongRangeExprIDs: Set<Int32> {
            get { memberships[Classification.ulongRange.rawValue] }
            set { memberships[Classification.ulongRange.rawValue] = newValue }
            _modify { yield &memberships[Classification.ulongRange.rawValue] }
        }

        var stringExprIDs: Set<Int32> {
            get { memberships[Classification.string.rawValue] }
            set { memberships[Classification.string.rawValue] = newValue }
            _modify { yield &memberships[Classification.string.rawValue] }
        }

        var fileExprIDs: Set<Int32> {
            get { memberships[Classification.file.rawValue] }
            set { memberships[Classification.file.rawValue] = newValue }
            _modify { yield &memberships[Classification.file.rawValue] }
        }

        var pathExprIDs: Set<Int32> {
            get { memberships[Classification.path.rawValue] }
            set { memberships[Classification.path.rawValue] = newValue }
            _modify { yield &memberships[Classification.path.rawValue] }
        }

        var listIteratorExprIDs: Set<Int32> {
            get { memberships[Classification.listIterator.rawValue] }
            set { memberships[Classification.listIterator.rawValue] = newValue }
            _modify { yield &memberships[Classification.listIterator.rawValue] }
        }

        var mapIteratorExprIDs: Set<Int32> {
            get { memberships[Classification.mapIterator.rawValue] }
            set { memberships[Classification.mapIterator.rawValue] = newValue }
            _modify { yield &memberships[Classification.mapIterator.rawValue] }
        }

        var iteratorBuilderExprIDs: Set<Int32> {
            get { memberships[Classification.iteratorBuilder.rawValue] }
            set { memberships[Classification.iteratorBuilder.rawValue] = newValue }
            _modify { yield &memberships[Classification.iteratorBuilder.rawValue] }
        }

        var ulongRangeIteratorExprIDs: Set<Int32> {
            get { memberships[Classification.ulongRangeIterator.rawValue] }
            set { memberships[Classification.ulongRangeIterator.rawValue] = newValue }
            _modify { yield &memberships[Classification.ulongRangeIterator.rawValue] }
        }

        subscript(exprID: KIRExprID) -> ClassificationFacts {
            get {
                var facts = ClassificationFacts()
                for classification in Classification.allCases
                where memberships[classification.rawValue].contains(exprID.rawValue) {
                    facts.insert(ClassificationFacts(classification))
                }
                return facts
            }
            set {
                for classification in Classification.allCases {
                    let isClassified = newValue.contains(classification)
                    if isClassified {
                        memberships[classification.rawValue].insert(exprID.rawValue)
                    } else {
                        memberships[classification.rawValue].remove(exprID.rawValue)
                    }
                }
            }
        }

        func contains(_ classification: Classification, _ exprID: KIRExprID) -> Bool {
            memberships[classification.rawValue].contains(exprID.rawValue)
        }

        mutating func insert(_ classification: Classification, _ exprID: KIRExprID) {
            memberships[classification.rawValue].insert(exprID.rawValue)
        }

        mutating func remove(_ classification: Classification, _ exprID: KIRExprID) {
            memberships[classification.rawValue].remove(exprID.rawValue)
        }

        mutating func copyFacts(from: KIRExprID, to: KIRExprID) {
            for classification in Classification.allCases {
                if memberships[classification.rawValue].contains(from.rawValue) {
                    memberships[classification.rawValue].insert(to.rawValue)
                } else {
                    memberships[classification.rawValue].remove(to.rawValue)
                }
            }
        }

        mutating func tagResult(
            _ classification: Classification,
            _ result: KIRExprID?,
            temporary: KIRExprID? = nil
        ) {
            guard let result else { return }
            insert(classification, result)
            if let temporary {
                insert(classification, temporary)
            }
        }

        mutating func tagListResult(_ result: KIRExprID?, temporary: KIRExprID? = nil) {
            tagResult(.list, result, temporary: temporary)
        }

        mutating func tagMapResult(_ result: KIRExprID?, temporary: KIRExprID? = nil) {
            tagResult(.map, result, temporary: temporary)
        }

        mutating func tag(_ expr: KIRExprID, as kind: CollectionLiteralTrackedStaticTypeKind) {
            insert(Classification(kind), expr)
        }

        mutating func propagateCopy(from: KIRExprID, to: KIRExprID) {
            copyFacts(from: from, to: to)
        }

        mutating func seedCopy(from: KIRExprID, to: KIRExprID) {
            self[to] = self[to].union(self[from])
        }

        /// ``Classification/sequence`` (confirmed `RuntimeSequenceBox`) and
        /// ``Classification/sequenceSourceObject`` (confirmed source object)
        /// are mutually exclusive facts about a single runtime value, but
        /// `seedCopy`'s union has no way to know that two copies into the
        /// same reused expression slot came from different branches of an
        /// `if`/`when` rather than agreeing evidence about the same value.
        /// A slot carrying both after such a union is asserting a fact no
        /// single execution can back up, so this drops the provenance
        /// entirely instead of keeping either guess — the caller must call
        /// this after every `seedCopy` that can touch a Sequence value.
        /// ``Classification/sequenceType`` (Sequence-typed, origin unknown)
        /// is unaffected: it is not a provenance claim, so it is never
        /// contradictory.
        mutating func resolveSequenceProvenanceConflicts(at expr: KIRExprID) {
            guard contains(.sequence, expr), contains(.sequenceSourceObject, expr) else { return }
            remove(.sequence, expr)
            remove(.sequenceSourceObject, expr)
        }

        func sequenceRuntimeRepresentation(
            of expr: KIRExprID
        ) -> SequenceRuntimeRepresentation {
            let facts = self[expr]
            let runtimeFacts = facts.facts(on: .runtimeRepresentation)
            let hasRuntimeBox = runtimeFacts.contains(.sequence)
            let hasSourceObject = runtimeFacts.contains(.sequenceSourceObject)
            let hasOtherRuntimeFact = runtimeFacts.classifications.contains {
                $0 != .sequence && $0 != .sequenceSourceObject
            }

            if hasRuntimeBox && hasSourceObject {
                return .unknown
            }
            if hasOtherRuntimeFact && (hasRuntimeBox || hasSourceObject) {
                return .unknown
            }
            if hasRuntimeBox {
                return .runtimeBox
            }
            if hasSourceObject {
                return .sourceObject
            }

            let staticFacts = facts.facts(on: .staticType)
            let hasStaticSequence = staticFacts.contains(.sequenceType)
            if hasStaticSequence {
                return .unknown
            }
            if !staticFacts.isEmpty || !runtimeFacts.isEmpty {
                return .notSequence
            }
            return .unknown
        }
    }

    enum CollectionRewriteTrackedResult {
        case list
        case set
        case map
        case array
        case sequence
        case range
        case listIterator

        func insert(_ expression: KIRExprID, into state: inout CollectionRewriteState) {
            switch self {
            case .list:
                state.listExprIDs.insert(expression.rawValue)
            case .set:
                state.setExprIDs.insert(expression.rawValue)
            case .map:
                state.mapExprIDs.insert(expression.rawValue)
            case .array:
                state.arrayExprIDs.insert(expression.rawValue)
            case .sequence:
                state.sequenceExprIDs.insert(expression.rawValue)
            case .range:
                state.rangeExprIDs.insert(expression.rawValue)
            case .listIterator:
                state.listIteratorExprIDs.insert(expression.rawValue)
            }
        }
    }

    @discardableResult
    func appendCallWithTrackedResult(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        trackedAs: CollectionRewriteTrackedResult?,
        trackTemporaryWithoutDestination: Bool = false,
        module: KIRModule,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let callResult = module.arena.appendTemporary(type: nil)
        loweredBody.append(.call(callee: callee, arguments: arguments, result: callResult, canThrow: canThrow, thrownResult: thrownResult))

        if trackTemporaryWithoutDestination {
            trackedAs?.insert(callResult, into: &state)
        }
        if let result {
            trackedAs?.insert(result, into: &state)
            if !trackTemporaryWithoutDestination {
                trackedAs?.insert(callResult, into: &state)
            }
            loweredBody.append(.copy(from: callResult, to: result))
        }
        return callResult
    }
}
