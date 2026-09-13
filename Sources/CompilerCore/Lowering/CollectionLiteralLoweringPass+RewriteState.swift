extension CollectionLiteralLoweringSupport {
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

        mutating func tagListResult(_ result: KIRExprID?, temporary: KIRExprID? = nil) {
            guard let result else { return }
            listExprIDs.insert(result.rawValue)
            if let temporary {
                listExprIDs.insert(temporary.rawValue)
            }
        }

        mutating func tagMapResult(_ result: KIRExprID?, temporary: KIRExprID? = nil) {
            guard let result else { return }
            mapExprIDs.insert(result.rawValue)
            if let temporary {
                mapExprIDs.insert(temporary.rawValue)
            }
        }

        /// Record the classification implied by a tracked static type. The
        /// kind-to-storage mapping lives here so callers that resolve a
        /// `CollectionLiteralTrackedStaticTypeKind` do not each name a set.
        mutating func tag(_ expr: KIRExprID, as kind: CollectionLiteralTrackedStaticTypeKind) {
            switch kind {
            case .list:
                listExprIDs.insert(expr.rawValue)
            case .set:
                setExprIDs.insert(expr.rawValue)
            case .map:
                mapExprIDs.insert(expr.rawValue)
            case .array:
                arrayExprIDs.insert(expr.rawValue)
            case .sequence:
                sequenceExprIDs.insert(expr.rawValue)
            case .string:
                stringExprIDs.insert(expr.rawValue)
            }
        }

        mutating func propagateCopy(from: KIRExprID, to: KIRExprID) {
            // Mutable locals reuse their expression ID. A copy replaces its
            // value, so facts about the previous value must not survive it.
            forEachClassification { expressions in
                if expressions.contains(from.rawValue) {
                    expressions.insert(to.rawValue)
                } else {
                    expressions.remove(to.rawValue)
                }
            }
        }

        /// Add what a copy proves while the pre-scan is still seeding this
        /// state, keeping facts the destination already carries from an
        /// earlier seed such as its static type.
        ///
        /// The pre-scan walks one function body forward from an empty state,
        /// so a destination already classified here was classified by a
        /// previous seed rather than by the value this copy overwrites.
        /// `propagateCopy` applies the replacement when the rewrite reaches
        /// the same copy, which keeps the classification visible to the
        /// instructions that precede it.
        mutating func seedCopy(from: KIRExprID, to: KIRExprID) {
            forEachClassification { expressions in
                if expressions.contains(from.rawValue) {
                    expressions.insert(to.rawValue)
                }
            }
        }

        /// Visit every classification set. Copy propagation and any other
        /// whole-state operation enumerate the kinds here, so adding a
        /// classification wires it into all of them at once.
        private mutating func forEachClassification(
            _ body: (inout Set<Int32>) -> Void
        ) {
            body(&listExprIDs)
            body(&setExprIDs)
            body(&mapExprIDs)
            body(&arrayExprIDs)
            body(&sequenceExprIDs)
            body(&rangeExprIDs)
            body(&charRangeExprIDs)
            body(&ulongRangeExprIDs)
            body(&stringExprIDs)
            body(&fileExprIDs)
            body(&pathExprIDs)
            body(&listIteratorExprIDs)
            body(&mapIteratorExprIDs)
            body(&iteratorBuilderExprIDs)
            body(&indexingIterableExprIDs)
            body(&indexingIterableIteratorExprIDs)
            body(&ulongRangeIteratorExprIDs)
        }
    }
}
