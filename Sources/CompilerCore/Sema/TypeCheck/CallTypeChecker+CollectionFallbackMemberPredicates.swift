import RuntimeABI

/// Supported-member, collection-returning, and arity predicates for
/// Collection member-call fallbacks, plus the `StdlibSurfaceSpec`
/// lookup helpers they share.
///
/// Split out from `CallTypeChecker+CollectionMemberFallback.swift`.
extension CallTypeChecker {
    func stdlibSurfaceOwnerKindsForCollectionFallback(
        isIterableReceiver: Bool,
        isListReceiver: Bool,
        isSequenceReceiver: Bool,
        isMapReceiver: Bool,
        isSetReceiver: Bool
    ) -> [StdlibSurfaceOwnerKind] {
        if isMapReceiver {
            return [.map]
        }
        if isSequenceReceiver {
            return [.sequence]
        }
        if isSetReceiver {
            return [.set]
        }
        if isIterableReceiver || isListReceiver {
            return [.list]
        }
        return []
    }

    private func stdlibSurfaceSpecsForCollectionFallback(
        memberName: InternedString,
        ownerKinds: [StdlibSurfaceOwnerKind],
        interner: StringInterner
    ) -> [StdlibSurfaceSpec] {
        let resolvedName = interner.resolve(memberName)
        return ownerKinds.flatMap { ownerKind in
            StdlibSurfaceSpec.collectionHOFSpecs(ownerKind: ownerKind, memberName: resolvedName)
        }
    }

    func stdlibSurfaceSpecForCollectionFallback(
        memberName: InternedString,
        argCount: Int,
        ownerKinds: [StdlibSurfaceOwnerKind],
        interner: StringInterner
    ) -> StdlibSurfaceSpec? {
        stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: ownerKinds,
            interner: interner
        )
        .first { $0.arity.accepts(argCount) }
    }

    private func stdlibSurfaceCollectionReturning(_ spec: StdlibSurfaceSpec) -> Bool {
        switch spec.returnStrategy {
        case .destinationArgument, .list, .set, .map, .sequence, .receiver:
            return true
        case .any, .nullableAny, .receiverElement, .nullableReceiverElement,
             .unit, .boolean, .int, .double:
            return false
        }
    }

    func isSetReturningCollectionBinaryMember(
        _ memberName: InternedString,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        return knownNames.setReturningCollectionBinaryMembers.contains(memberName)
    }

    func isSupportedCollectionFallbackMember(
        _ memberName: InternedString,
        isIterableReceiver: Bool,
        isListReceiver: Bool,
        isSequenceReceiver: Bool,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isMutableCollectionReceiver: Bool,
        isMutableListReceiver: Bool,
        isMutableSetReceiver: Bool = false,
        isMutableMapReceiver: Bool,
        isAddAllArrayArgument: Bool = false,
        isAddAllSequenceArgument: Bool = false,
        isAddAllIterableArgument: Bool = false,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        // Sequence.zip is source-backed and must validate its argument through
        // overload resolution; reversed is not available on Sequence at all.
        if isSequenceReceiver, memberName == knownNames.reversed || memberName == knownNames.zip {
            return false
        }
        // KUU-1413: kotlin.sequences has no reduceRight family (a one-pass
        // Sequence cannot fold from the right), so the legacy collection
        // fallback must not admit these names for a Sequence receiver either.
        if isSequenceReceiver,
           memberName == knownNames.reduceRight
               || memberName == knownNames.reduceRightIndexed
               || memberName == knownNames.reduceRightOrNull
               || memberName == knownNames.reduceRightIndexedOrNull
        {
            return false
        }
        let surfaceOwnerKinds = stdlibSurfaceOwnerKindsForCollectionFallback(
            isIterableReceiver: isIterableReceiver,
            isListReceiver: isListReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver
        )
        if !stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ).isEmpty {
            return true
        }
        let collectionMembers = knownNames.collectionMembers
        let listOnlyMembers = knownNames.listOnlyMembers
        let collectionSpecificMembers = knownNames.collectionSpecificMembers
        let mutableListOnlyMembers = knownNames.mutableListOnlyMembers
        let mutableCollectionMembers = knownNames.mutableCollectionMembers
        let mapOnlyMembers = knownNames.mapOnlyMembers
        if listOnlyMembers.contains(memberName) {
            return isListReceiver
        }
        if collectionSpecificMembers.contains(memberName) {
            return isListReceiver || isSetReceiver || isSequenceReceiver
        }
        if memberName == knownNames.getOrElse {
            return isListReceiver || isMapReceiver
        }
        if memberName == knownNames.elementAtOrElse {
            return isListReceiver
        }
        if memberName == knownNames.minus {
            return isMapReceiver || isListReceiver || isSetReceiver
        }
        if mapOnlyMembers.contains(memberName) {
            return isMapReceiver
        }
        if isSetReturningCollectionBinaryMember(memberName, interner: interner) {
            return isListReceiver || isSetReceiver
        }
        if mutableListOnlyMembers.contains(memberName) {
            return isMutableListReceiver
        }
        if mutableCollectionMembers.contains(memberName) {
            return isMutableListReceiver
                || isMutableSetReceiver
                || (memberName == knownNames.add && isMutableCollectionReceiver)
                || (
                    memberName == knownNames.addAll
                        && isMutableCollectionReceiver
                        && (isAddAllArrayArgument || isAddAllSequenceArgument || isAddAllIterableArgument)
                )
        }
        if memberName == knownNames.getOrPut || memberName == knownNames.putAll {
            return isMutableMapReceiver
        }
        if memberName == knownNames.requireNoNulls {
            return isIterableReceiver || isListReceiver || isSetReceiver || isSequenceReceiver
        }
        // KUU-1362: Map is not an Iterable in Kotlin. Iterable/Collection-only
        // members (filterNotNull, first, fold, distinct, ...) must not be
        // admitted for a Map receiver — they previously bound a result type
        // with no callee and lowered to undefined symbols (LINK-0001).
        if isMapReceiver {
            return knownNames.mapMembers.contains(memberName)
        }
        return collectionMembers.contains(memberName)
    }

    func isCollectionReturningMember(
        _ memberName: InternedString,
        isMapReceiver: Bool,
        isListReceiver: Bool,
        isSetReceiver: Bool,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let surfaceOwnerKinds: [StdlibSurfaceOwnerKind] = if isMapReceiver {
            [.map]
        } else if isSetReceiver {
            [.set]
        } else if isListReceiver {
            [.list]
        } else {
            []
        }
        if let spec = stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ).first {
            return stdlibSurfaceCollectionReturning(spec)
        }

        let collectionReturningMembers = knownNames.collectionReturningMembers
        if memberName == knownNames.plus ||
            memberName == knownNames.minus
        {
            return isMapReceiver
        }
        if isSetReturningCollectionBinaryMember(memberName, interner: interner) {
            return isListReceiver || isSetReceiver
        }
        return collectionReturningMembers.contains(memberName)
    }

    func isValidCollectionFallbackArity(
        _ memberName: InternedString,
        argCount: Int,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isSequenceReceiver: Bool,
        isListReceiver: Bool,
        isMutableCollectionReceiver: Bool,
        isMutableMapReceiver: Bool,
        isMutableSetReceiver: Bool = false,
        isMutableListReceiver: Bool,
        isAddAllArrayArgument: Bool = false,
        isAddAllSequenceArgument: Bool = false,
        isAddAllIterableArgument: Bool = false,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let surfaceOwnerKinds = stdlibSurfaceOwnerKindsForCollectionFallback(
            isIterableReceiver: true,
            isListReceiver: true,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver
        )
        let surfaceSpecs = stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        )
        if surfaceSpecs.contains(where: { $0.arity.accepts(argCount) }) {
            return true
        }
        if isSetReturningCollectionBinaryMember(memberName, interner: interner) {
            return (isListReceiver || isSetReceiver) && argCount == 1
        }
        // KUU-1362: same Map/Iterable split as isSupportedCollectionFallbackMember.
        if isMapReceiver, !knownNames.mapMembers.contains(memberName) {
            return false
        }
        switch memberName {
        case knownNames.size, knownNames.isEmpty, knownNames.iterator, knownNames.asSequence,
             knownNames.asIterable,
             knownNames.toList, knownNames.toTypedArray, knownNames.reversed,
            knownNames.asReversed, knownNames.sorted,
             knownNames.distinct, knownNames.flatten, knownNames.withIndex,
             knownNames.min, knownNames.maxOrNull, knownNames.minOrNull, knownNames.sortedDescending, knownNames.filterIsInstance,
             knownNames.firstOrNull, knownNames.lastOrNull, knownNames.singleOrNull, knownNames.sort,
             knownNames.toMutableList, knownNames.sum, knownNames.average,
             knownNames.requireNoNulls:
            return argCount == 0
        case knownNames.filter:
            return argCount == 1
        case knownNames.joinToString:
            return (0 ... 4).contains(argCount)
        case knownNames.shuffled:
            return argCount == 0 || argCount == 1
        case knownNames.filterNotNull, knownNames.unzip, knownNames.eachCount:
            return argCount == 0
        case knownNames.get, knownNames.getOrNull, knownNames.elementAtOrNull,
             knownNames.containsAll, knownNames.indexOf, knownNames.lastIndexOf, knownNames.indexOfFirst, knownNames.indexOfLast, knownNames.binarySearch,
             knownNames.sortedBy, knownNames.find, knownNames.reduce, knownNames.reduceOrNull, knownNames.reduceIndexedOrNull, knownNames.runningReduce, knownNames.runningReduceIndexed, knownNames.take, knownNames.drop, knownNames.zip,
             knownNames.filterIndexed,
             knownNames.sortedByDescending, knownNames.sortedWith, knownNames.partition,
             knownNames.sortBy, knownNames.sortByDescending, knownNames.distinctBy,
             knownNames.maxBy, knownNames.minBy, knownNames.maxByOrNull, knownNames.minByOrNull,
             knownNames.maxOfOrNull, knownNames.minOfOrNull,
             knownNames.maxOf, knownNames.minOf,
             knownNames.maxWith, knownNames.maxWithOrNull,
             knownNames.minWith, knownNames.minWithOrNull,
             knownNames.elementAt,
             knownNames.minusElement:
            if memberName == knownNames.binarySearch {
                return (1...4).contains(argCount)
            }
            return argCount == 1
        case knownNames.binarySearchBy:
            return argCount == 2 || argCount == 3 || argCount == 4
        case knownNames.toCollection, knownNames.filterIsInstanceTo, knownNames.filterNotNullTo:
            return argCount == 1
        case knownNames.reduceTo:
            return argCount == 2
        case knownNames.containsKey:
            return isMapReceiver && argCount == 1
        case knownNames.getValue:
            return isMapReceiver && argCount == 1
        case knownNames.getOrDefault:
            return isMapReceiver && argCount == 2
        case knownNames.getOrElse:
            return argCount == 2
        case knownNames.elementAtOrElse:
            return argCount == 2
        case knownNames.getOrPut:
            return isMutableMapReceiver && argCount == 2
        case knownNames.add, knownNames.addAll, knownNames.remove, knownNames.removeAll,
             knownNames.retainAll:
            return (
                isMutableListReceiver
                    || isMutableSetReceiver
                    || (memberName == knownNames.add && isMutableCollectionReceiver)
                    || (
                        memberName == knownNames.addAll
                            && isMutableCollectionReceiver
                            && (isAddAllArrayArgument || isAddAllSequenceArgument || isAddAllIterableArgument)
                    )
            ) && argCount == 1
        case knownNames.clear:
            return (isMutableListReceiver || isMutableSetReceiver) && argCount == 0
        case knownNames.putAll:
            return isMutableMapReceiver && argCount == 1
        case knownNames.plus:
            return isMapReceiver && argCount == 1
        case knownNames.minus:
            return (isMapReceiver || isListReceiver || isSetReceiver) && argCount == 1
        case knownNames.fold, knownNames.foldRight, knownNames.foldIndexed, knownNames.foldRightIndexed, knownNames.scan, knownNames.scanIndexed, knownNames.runningFold, knownNames.runningFoldIndexed, knownNames.subList:
            return argCount == 2
        case knownNames.slice:
            return argCount == 1
        case knownNames.reduceRight, knownNames.reduceRightIndexed, knownNames.reduceRightIndexedOrNull, knownNames.reduceRightOrNull, knownNames.reduceIndexed:
            return argCount == 1
        case knownNames.windowed:
            return argCount == 1 || argCount == 2 || argCount == 3 || argCount == 4
        case knownNames.chunked:
            return argCount == 1 || argCount == 2
        case knownNames.count, knownNames.first, knownNames.last,
             knownNames.single:
            return argCount == 0 || argCount == 1
        default:
            return true
        }
    }
}
