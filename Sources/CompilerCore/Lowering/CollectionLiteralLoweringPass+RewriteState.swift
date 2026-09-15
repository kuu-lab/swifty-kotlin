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
        case indexingIterable
        case indexingIterableIterator
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
                 .listIterator, .mapIterator, .iteratorBuilder, .indexingIterable,
                 .indexingIterableIterator, .ulongRangeIterator:
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

    /// Runtime representation evidence for a value that may be a Sequence.
    ///
    /// The static `Sequence` type is intentionally not represented by either
    /// `runtimeBox` or `sourceObject`: both representations satisfy that
    /// interface, and the type alone cannot select the bridge safely.  The
    /// `notSequence` case lets callers distinguish a known non-Sequence
    /// receiver (for example, a List `map`) from a Sequence value whose origin
    /// is simply unavailable.  Unknown values must stay on the original
    /// iterator path rather than being guessed to be source-backed.
    enum SequenceRuntimeRepresentation: Equatable, Sendable {
        /// A confirmed `RuntimeSequenceBox` handle.
        case runtimeBox
        /// A confirmed source-backed `object : Sequence<T>` value.
        case sourceObject
        /// The receiver is known not to be a Sequence value.
        case notSequence
        /// Sequence-typed or otherwise insufficiently classified; no runtime
        /// representation may be selected from the available facts.
        case unknown
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
    /// expression, for two measured reasons written up under the
    /// RF-LOWER-STATE-002 task entry. Storing `[KIRExprID: ClassificationFacts]`
    /// instead would make every `contains` rebuild a set, which measured 150x
    /// slower at 200 expressions per function and 12000x at 4000. And the
    /// per-classification sets remain *stored* properties because the
    /// virtual-call leaf rewrites still receive them as separate `inout`
    /// arguments — Swift allows that only for distinct storage, not for
    /// computed views. RF-LOWER-STATE-005 onwards retires those parameter
    /// lists, after which the named sets can become views over a single
    /// container (RF-LOWER-STATE-010).
    ///
    /// ``membership(of:)`` and ``mutateMembership(of:_:)`` are the only places
    /// that map a classification to its storage. Both switch exhaustively, so
    /// adding a classification cannot silently skip copy propagation.
    struct CollectionRewriteState {
        var listExprIDs: Set<Int32> = []
        var setExprIDs: Set<Int32> = []
        var mapExprIDs: Set<Int32> = []
        var arrayExprIDs: Set<Int32> = []
        var sequenceExprIDs: Set<Int32> = []
        var sequenceSourceObjectExprIDs: Set<Int32> = []
        var sequenceTypeExprIDs: Set<Int32> = []
        var rangeExprIDs: Set<Int32> = []
        var charRangeExprIDs: Set<Int32> = []
        var ulongRangeExprIDs: Set<Int32> = []
        var stringExprIDs: Set<Int32> = []
        var fileExprIDs: Set<Int32> = []
        var pathExprIDs: Set<Int32> = []

        var listIteratorExprIDs: Set<Int32> = []
        var mapIteratorExprIDs: Set<Int32> = []
        var iteratorBuilderExprIDs: Set<Int32> = []
        var indexingIterableExprIDs: Set<Int32> = []
        var indexingIterableIteratorExprIDs: Set<Int32> = []
        var ulongRangeIteratorExprIDs: Set<Int32> = []

        // MARK: - Storage manifest

        /// Every expression carrying `classification`.
        func membership(of classification: Classification) -> Set<Int32> {
            switch classification {
            case .list: listExprIDs
            case .set: setExprIDs
            case .map: mapExprIDs
            case .array: arrayExprIDs
            case .sequence: sequenceExprIDs
            case .sequenceSourceObject: sequenceSourceObjectExprIDs
            case .sequenceType: sequenceTypeExprIDs
            case .range: rangeExprIDs
            case .charRange: charRangeExprIDs
            case .ulongRange: ulongRangeExprIDs
            case .string: stringExprIDs
            case .file: fileExprIDs
            case .path: pathExprIDs
            case .listIterator: listIteratorExprIDs
            case .mapIterator: mapIteratorExprIDs
            case .iteratorBuilder: iteratorBuilderExprIDs
            case .indexingIterable: indexingIterableExprIDs
            case .indexingIterableIterator: indexingIterableIteratorExprIDs
            case .ulongRangeIterator: ulongRangeIteratorExprIDs
            }
        }

        /// Mutate `classification`'s membership in place.
        ///
        /// The set is yielded rather than returned so the caller mutates the
        /// stored property directly; handing back a copy would duplicate the
        /// whole set on every insert.
        mutating func mutateMembership(
            of classification: Classification,
            _ body: (inout Set<Int32>) -> Void
        ) {
            switch classification {
            case .list: body(&listExprIDs)
            case .set: body(&setExprIDs)
            case .map: body(&mapExprIDs)
            case .array: body(&arrayExprIDs)
            case .sequence: body(&sequenceExprIDs)
            case .sequenceSourceObject: body(&sequenceSourceObjectExprIDs)
            case .sequenceType: body(&sequenceTypeExprIDs)
            case .range: body(&rangeExprIDs)
            case .charRange: body(&charRangeExprIDs)
            case .ulongRange: body(&ulongRangeExprIDs)
            case .string: body(&stringExprIDs)
            case .file: body(&fileExprIDs)
            case .path: body(&pathExprIDs)
            case .listIterator: body(&listIteratorExprIDs)
            case .mapIterator: body(&mapIteratorExprIDs)
            case .iteratorBuilder: body(&iteratorBuilderExprIDs)
            case .indexingIterable: body(&indexingIterableExprIDs)
            case .indexingIterableIterator: body(&indexingIterableIteratorExprIDs)
            case .ulongRangeIterator: body(&ulongRangeIteratorExprIDs)
            }
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
                where membership(of: classification).contains(exprID.rawValue) {
                    facts.insert(ClassificationFacts(classification))
                }
                return facts
            }
            set {
                for classification in Classification.allCases {
                    let isClassified = newValue.contains(classification)
                    mutateMembership(of: classification) { membership in
                        if isClassified {
                            membership.insert(exprID.rawValue)
                        } else {
                            membership.remove(exprID.rawValue)
                        }
                    }
                }
            }
        }

        func contains(_ classification: Classification, _ exprID: KIRExprID) -> Bool {
            membership(of: classification).contains(exprID.rawValue)
        }

        mutating func insert(_ classification: Classification, _ exprID: KIRExprID) {
            mutateMembership(of: classification) { $0.insert(exprID.rawValue) }
        }

        mutating func remove(_ classification: Classification, _ exprID: KIRExprID) {
            mutateMembership(of: classification) { $0.remove(exprID.rawValue) }
        }

        /// Replace everything known about `to` with everything known about `from`.
        ///
        /// Mutable locals reuse their expression ID. A copy replaces their value,
        /// so facts about the previous value must not survive it — including when
        /// `from` carries no facts at all.
        mutating func copyFacts(from: KIRExprID, to: KIRExprID) {
            for classification in Classification.allCases {
                mutateMembership(of: classification) { membership in
                    if membership.contains(from.rawValue) {
                        membership.insert(to.rawValue)
                    } else {
                        membership.remove(to.rawValue)
                    }
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

        /// Resolve the runtime representation that is safe to use for a
        /// Sequence bridge decision.
        ///
        /// Provenance facts are authoritative when they are exclusive. A
        /// contradictory runtime union is conservative: it becomes unknown
        /// instead of selecting either side. A static `Sequence` fact carries
        /// no provenance and therefore also remains unknown. Other static or
        /// runtime classifications prove that the value is not a Sequence.
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
}
