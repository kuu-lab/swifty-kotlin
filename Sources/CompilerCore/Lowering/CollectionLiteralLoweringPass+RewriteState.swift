extension CollectionLiteralLoweringSupport {
    /// Axis a classification fact is recorded on.
    ///
    /// Facts on different axes answer different questions about the same value,
    /// so a value can carry facts on both, and "unknown" is meaningful per axis
    /// rather than only for a value carrying no facts at all.
    enum ClassificationAxis: Sendable, CaseIterable {
        /// What kind of collection the value is, as far as its declared type or
        /// the factory that produced it says.
        ///
        /// This axis does not yet distinguish a declared type from a factory
        /// call or a runtime bridge that produced the value; recording only the
        /// provenance that is actually known is RF-LOWER-STATE-009's job.
        case staticType
        /// Which runtime representation holds the value. Only lowering records
        /// these, when it materialises the runtime handle itself.
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
        case sequence
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

        var axis: ClassificationAxis {
            switch self {
            case .list, .set, .map, .array, .sequence, .range, .charRange,
                 .ulongRange, .string, .file, .path:
                .staticType
            case .listIterator, .mapIterator, .iteratorBuilder, .indexingIterable,
                 .indexingIterableIterator, .ulongRangeIterator:
                .runtimeRepresentation
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
    /// expression, for two measured reasons written up under the
    /// RF-LOWER-STATE-002 task entry. Storing `[KIRExprID: ClassificationFacts]`
    /// instead would make every `contains` rebuild a set, which measured 150x
    /// slower at 200 expressions per function and 12000x at 4000. And the
    /// per-classification sets have to be *stored* properties for now, because
    /// the registry still hands several of them to one callee as separate
    /// `inout` arguments — Swift allows that only for distinct storage, not for
    /// computed views. RF-LOWER-STATE-003 and 004 remove those argument lists,
    /// after which the named sets can become views over a single container.
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

        mutating func propagateCopy(from: KIRExprID, to: KIRExprID) {
            copyFacts(from: from, to: to)
        }
    }
}
