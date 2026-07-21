extension CollectionLiteralLoweringSupport {
    enum ComparatorSource {
        case ascending
        case descending
        case multiSelector
        case naturalOrder
        case reverseOrder
        case thenBy(inner: KIRExprID)
        case thenByDescending(inner: KIRExprID)
        case thenDescending(inner: KIRExprID)
        case thenComparator(inner: KIRExprID)
        case nullsFirst(inner: KIRExprID)
        case nullsLast(inner: KIRExprID)
        /// The comparator was produced by the zero-arg `nullsFirst()` (Comparable version).
        case nullsFirstComparable
        case nullsLastNatural
        /// The comparator was produced by `Comparator.reversed()`.
        /// The associated KIRExprID is the inner comparator expression.
        case reversed(inner: KIRExprID)
        case unknown
    }

    func isComparatorFromCall(
        exprID: KIRExprID,
        body: [KIRInstruction],
        ascendingCallee: InternedString,
        descendingCallee: InternedString,
        multiSelectorCallee: InternedString,
        naturalOrderCallee: InternedString,
        reverseOrderCallee: InternedString,
        thenByCallee: InternedString? = nil,
        thenByDescendingCallee: InternedString? = nil,
        thenDescendingCallee: InternedString? = nil,
        thenComparatorCallee: InternedString? = nil,
        nullsFirstCallee: InternedString? = nil,
        nullsLastCallee: InternedString? = nil,
        nullsFirstComparableCallee: InternedString? = nil,
        nullsLastNaturalCallee: InternedString? = nil,
        multiSelector3Callee: InternedString? = nil,
        multiSelectorVarargCallee: InternedString? = nil,
        reversedCallee: InternedString? = nil
    ) -> ComparatorSource {
        for inst in body {
            switch inst {
            case let .call(_, callee, arguments, result, _, _, _, _):
                if let result, result.rawValue == exprID.rawValue {
                    if callee == ascendingCallee { return .ascending }
                    if callee == descendingCallee { return .descending }
                    if callee == multiSelectorCallee { return .multiSelector }
                    if let ms3 = multiSelector3Callee, callee == ms3 { return .multiSelector }
                    if let msVararg = multiSelectorVarargCallee, callee == msVararg { return .multiSelector }
                    if callee == naturalOrderCallee { return .naturalOrder }
                    if callee == reverseOrderCallee { return .reverseOrder }
                    if let thenBy = thenByCallee, callee == thenBy, let innerExpr = arguments.first {
                        return .thenBy(inner: innerExpr)
                    }
                    if let thenByDescending = thenByDescendingCallee, callee == thenByDescending, let innerExpr = arguments.first {
                        return .thenByDescending(inner: innerExpr)
                    }
                    if let thenDescending = thenDescendingCallee, callee == thenDescending, let innerExpr = arguments.first {
                        return .thenDescending(inner: innerExpr)
                    }
                    if let thenComparator = thenComparatorCallee, callee == thenComparator, let innerExpr = arguments.first {
                        return .thenComparator(inner: innerExpr)
                    }
                    if let nullsFirst = nullsFirstCallee, callee == nullsFirst, let innerExpr = arguments.first {
                        return .nullsFirst(inner: innerExpr)
                    }
                    if let nullsLast = nullsLastCallee, callee == nullsLast, let innerExpr = arguments.first {
                        return .nullsLast(inner: innerExpr)
                    }
                    if let nfc = nullsFirstComparableCallee, callee == nfc {
                        return .nullsFirstComparable
                    }
                    if let nullsLastNatural = nullsLastNaturalCallee, callee == nullsLastNatural {
                        return .nullsLastNatural
                    }
                    if let rc = reversedCallee, callee == rc, let innerExpr = arguments.first {
                        return .reversed(inner: innerExpr)
                    }
                    return .unknown
                }
            case let .copy(from: fromID, to: toID):
                if toID.rawValue == exprID.rawValue {
                    return isComparatorFromCall(
                        exprID: fromID,
                        body: body,
                        ascendingCallee: ascendingCallee,
                        descendingCallee: descendingCallee,
                        multiSelectorCallee: multiSelectorCallee,
                        naturalOrderCallee: naturalOrderCallee,
                        reverseOrderCallee: reverseOrderCallee,
                        thenByCallee: thenByCallee,
                        thenByDescendingCallee: thenByDescendingCallee,
                        thenDescendingCallee: thenDescendingCallee,
                        thenComparatorCallee: thenComparatorCallee,
                        nullsFirstCallee: nullsFirstCallee,
                        nullsLastCallee: nullsLastCallee,
                        nullsFirstComparableCallee: nullsFirstComparableCallee,
                        nullsLastNaturalCallee: nullsLastNaturalCallee,
                        multiSelector3Callee: multiSelector3Callee,
                        multiSelectorVarargCallee: multiSelectorVarargCallee,
                        reversedCallee: reversedCallee
                    )
                }
            default:
                break
            }
        }
        return .unknown
    }

    // Keep the reduced lookup surface for lowering paths that only retain
    // comparator wrappers and multi-selector factories.
    func isComparatorFromCall(
        exprID: KIRExprID,
        body: [KIRInstruction],
        multiSelectorCallee: InternedString,
        nullsFirstCallee: InternedString? = nil,
        nullsLastCallee: InternedString? = nil,
        nullsFirstComparableCallee: InternedString? = nil,
        nullsLastNaturalCallee: InternedString? = nil,
        multiSelector3Callee: InternedString? = nil,
        multiSelectorVarargCallee: InternedString? = nil
    ) -> ComparatorSource {
        for inst in body {
            switch inst {
            case let .call(_, callee, arguments, result, _, _, _, _):
                if let result, result.rawValue == exprID.rawValue {
                    if callee == multiSelectorCallee { return .multiSelector }
                    if let ms3 = multiSelector3Callee, callee == ms3 { return .multiSelector }
                    if let msVararg = multiSelectorVarargCallee, callee == msVararg { return .multiSelector }
                    if let nullsFirst = nullsFirstCallee, callee == nullsFirst, arguments.first != nil {
                        return .nullsFirst(inner: exprID)
                    }
                    if let nullsLast = nullsLastCallee, callee == nullsLast, arguments.first != nil {
                        return .nullsLast(inner: exprID)
                    }
                    if let nfc = nullsFirstComparableCallee, callee == nfc {
                        return .nullsFirstComparable
                    }
                    if let nullsLastNatural = nullsLastNaturalCallee, callee == nullsLastNatural {
                        return .nullsLastNatural
                    }
                    return .unknown
                }
            case let .copy(from: fromID, to: toID):
                if toID.rawValue == exprID.rawValue {
                    return isComparatorFromCall(
                        exprID: fromID,
                        body: body,
                        multiSelectorCallee: multiSelectorCallee,
                        nullsFirstCallee: nullsFirstCallee,
                        nullsLastCallee: nullsLastCallee,
                        nullsFirstComparableCallee: nullsFirstComparableCallee,
                        nullsLastNaturalCallee: nullsLastNaturalCallee,
                        multiSelector3Callee: multiSelector3Callee,
                        multiSelectorVarargCallee: multiSelectorVarargCallee
                    )
                }
            default:
                break
            }
        }
        return .unknown
    }

    func retainedComparatorRuntimePair(
        source: ComparatorSource,
        comparatorExpr: KIRExprID,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        loweredBody: inout [KIRInstruction]
    ) -> (trampolineName: InternedString, closureExpr: KIRExprID)? {
        switch source {
        case .multiSelector:
            return (lookup.kkComparatorFromMultiSelectorsTrampolineName, comparatorExpr)
        case .nullsFirst:
            return (lookup.kkComparatorNullsFirstTrampolineName, comparatorExpr)
        case .nullsLast:
            return (lookup.kkComparatorNullsLastTrampolineName, comparatorExpr)
        case .nullsFirstComparable:
            let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
            return (lookup.kkComparatorNullsFirstComparableTrampolineName, zero)
        case .nullsLastNatural:
            let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
            return (lookup.kkComparatorNullsLastNaturalTrampolineName, zero)
        case .unknown:
            return nil
        default:
            return nil
        }
    }
}
