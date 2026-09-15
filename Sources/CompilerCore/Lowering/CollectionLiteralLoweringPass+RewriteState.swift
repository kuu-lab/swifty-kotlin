extension CollectionLiteralLoweringSupport {
    /// Axis a classification fact is recorded on.
    ///
    /// Facts on different axes answer different questions about the same value,
    /// so a value can carry facts on both, and "unknown" is meaningful per axis
    /// rather than only for a value carrying no facts at all.
    enum ClassificationAxis: Sendable, CaseIterable {
        /// What kind of collection the value is, as far as its declared type
        /// says.
        ///
        /// RF-LOWER-STATE-009 split this axis from provenance: ``Classification/sequenceType``
        /// records only that the static type is `Sequence`, with no claim about
        /// which runtime representation backs the value — that lives on
        /// ``runtimeRepresentation`` as ``Classification/sequence`` /
        /// ``Classification/sequenceSourceObject``.
        case staticType
        /// Which runtime representation holds the value.
        ///
        /// Most of these are recorded only when lowering materialises the
        /// runtime handle itself. ``Classification/sequence`` and
        /// ``Classification/sequenceSourceObject`` are the exception
        /// (RF-LOWER-STATE-009): the pre-scan records them from confirmable
        /// evidence about a value that already exists — a known runtime
        /// factory/bridge, a source declaration confirmed to construct a fresh
        /// object, or a copy from a value already classified — never guessed
        /// from the static type alone.
        case runtimeRepresentation
    }

    /// One classification a rewrite can know about an expression.
    ///
    /// `rawValue` doubles as the bit position in ``ClassificationFacts``, so the
    /// cases must stay contiguous from zero.
    enum Classification: Int, CaseIterable, Sendable {
        case list
        case set
        case map
        case array
        /// Confirmed `RuntimeSequenceBox`: a known runtime factory/bridge
        /// produced this value, or the value was propagated from one that
        /// did. Despite the name this is a runtime-representation fact, not
        /// a static-type one — see ``sequenceType`` for "the static type is
        /// `Sequence`" and ``sequenceSourceObject`` for the other confirmed
        /// representation (RF-LOWER-STATE-009).
        case sequence
        /// Confirmed source-backed `Sequence` object (RF-LOWER-STATE-009): a
        /// bundled declaration whose body is confirmed, by reading it, to
        /// construct a fresh `object : Sequence<T>` rather than bridge to a
        /// runtime factory — or a value propagated from one that is.
        /// Mutually exclusive with ``sequence``; see
        /// ``CollectionRewriteState/resolveSequenceProvenanceConflicts(at:)``
        /// for what happens when a reused expression slot receives both.
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
        /// The static type is (or resolves to) `kotlin.sequences.Sequence`,
        /// with no claim about which runtime representation backs the value.
        /// Revives the static classification `trackedStaticTypeKind` stopped
        /// performing under KSP-441〜447; kept apart from ``sequence`` /
        /// ``sequenceSourceObject`` because a Sequence-typed value's runtime
        /// representation is not decidable from its static type alone
        /// (RF-LOWER-STATE-009).
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

        /// The classification a tracked static type implies.
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

    /// Every classification known about a single expression.
    ///
    /// A value routinely carries more than one: a `ULongRange` is both ``range``
    /// and ``ulongRange``, and collapsing those into a single kind loses the
    /// facts `step` / `reversed` need.
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

        /// The facts recorded on `axis` alone.
        func facts(on axis: ClassificationAxis) -> ClassificationFacts {
            intersection(.mask(for: axis))
        }

        /// Nothing is known about the value on `axis`.
        ///
        /// A value can be unknown on one axis while classified on the other, so
        /// callers must ask about the axis they care about instead of reading an
        /// empty fact set as the only form of unknown.
        func isUnknown(on axis: ClassificationAxis) -> Bool {
            facts(on: axis).isEmpty
        }

        var classifications: [Classification] {
            Classification.allCases.filter { contains($0) }
        }
    }

    /// The classification store: the one place facts about lowered expressions
    /// live, addressed by ``KIRExprID``.
    ///
    /// Facts are physically grouped per classification rather than per
    /// expression. The indexed store keeps membership checks O(1) without
    /// rebuilding a fact set for every expression, while the named accessors
    /// below preserve the old callers as mutable views over this one store.
    ///
    /// The virtual-call leaves now receive this state as a whole, so no caller
    /// needs simultaneous `inout` access to several named sets. That makes the
    /// views safe: there is one source of truth and copy propagation only has
    /// to iterate the classification enum.
    struct CollectionRewriteState {
        private var memberships = Array(
            repeating: Set<Int32>(),
            count: Classification.allCases.count
        )

        // MARK: - Named compatibility views

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

        // MARK: - Expression-keyed access

        /// Every classification known about `exprID`.
        ///
        /// Assigning replaces the expression's facts wholesale, so a fact the
        /// new value does not carry is cleared rather than left behind.
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

        /// Replace everything known about `to` with everything known about `from`.
        ///
        /// Mutable locals reuse their expression ID. A copy replaces their value,
        /// so facts about the previous value must not survive it — including when
        /// `from` carries no facts at all.
        mutating func copyFacts(from: KIRExprID, to: KIRExprID) {
            for classification in Classification.allCases {
                if memberships[classification.rawValue].contains(from.rawValue) {
                    memberships[classification.rawValue].insert(to.rawValue)
                } else {
                    memberships[classification.rawValue].remove(to.rawValue)
                }
            }
        }

        // MARK: - Result tagging

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

        /// Record the classification implied by a tracked static type, so
        /// callers that resolve a `CollectionLiteralTrackedStaticTypeKind` do
        /// not each name a set.
        mutating func tag(_ expr: KIRExprID, as kind: CollectionLiteralTrackedStaticTypeKind) {
            insert(Classification(kind), expr)
        }

        mutating func propagateCopy(from: KIRExprID, to: KIRExprID) {
            copyFacts(from: from, to: to)
        }

        /// Add what a copy proves while the pre-scan is still seeding this
        /// state, keeping facts the destination already carries from an
        /// earlier seed such as its static type.
        ///
        /// The pre-scan walks one function body forward from an empty state,
        /// so a destination already classified here was classified by a
        /// previous seed rather than by the value this copy overwrites.
        /// ``propagateCopy(from:to:)`` applies the replacement when the rewrite
        /// reaches the same copy, which keeps the classification visible to the
        /// instructions that precede it.
        mutating func seedCopy(from: KIRExprID, to: KIRExprID) {
            self[to] = self[to].union(self[from])
        }

        /// Drop Sequence provenance that a `seedCopy` union has made
        /// contradictory (RF-LOWER-STATE-009).
        ///
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
    }
}
