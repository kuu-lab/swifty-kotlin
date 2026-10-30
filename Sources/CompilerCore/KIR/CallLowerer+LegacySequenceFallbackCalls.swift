extension CallLowerer {

    private static let throwingSequenceSingleArgCallees: Set<String> = [
        "kk_sequence_sortedBy", "kk_sequence_sortedByDescending",
        "kk_sequence_takeLastWhile", "kk_sequence_takeLast",
        "kk_sequence_firstNotNullOf", "kk_sequence_firstNotNullOfOrNull",
        "kk_sequence_elementAt", "kk_sequence_elementAtOrElse",
        "kk_sequence_last", "__kk_iterable_last",
        "kk_sequence_min", "kk_sequence_max",
        "kk_sequence_any", "__kk_iterable_any",
        "kk_sequence_all", "__kk_iterable_all",
        "kk_sequence_none",
        "kk_sequence_indexOfFirst", "kk_sequence_indexOfLast",
        "kk_sequence_mapNotNull", "kk_sequence_mapIndexedNotNull",
        "kk_sequence_random", "kk_sequence_randomOrNull",
        "kk_sequence_mapIndexed", "kk_sequence_filterIndexed",
        "kk_sequence_onEach", "kk_sequence_onEachIndexed",
        "kk_sequence_reduceOrNull", "kk_sequence_reduce",
        "kk_sequence_reduceRight", "kk_sequence_reduceRightIndexed",
        "kk_sequence_reduceRightOrNull", "kk_sequence_reduceRightIndexedOrNull",
        "kk_sequence_runningReduceIndexed",
        "kk_sequence_ifEmpty",
    ]

    private static let lambdaSplitSequenceSingleArgCallees: Set<String> = [
        "kk_sequence_firstNotNullOf", "kk_sequence_firstNotNullOfOrNull",
        "kk_sequence_takeLastWhile",
        "kk_sequence_reduceOrNull",
        "kk_sequence_indexOfFirst",
        "kk_sequence_reduceRightIndexed", "kk_sequence_reduceRightOrNull",
        "kk_sequence_indexOfLast",
        "kk_sequence_reduceRight", "kk_sequence_reduce",
        "kk_sequence_reduceRightIndexedOrNull",
    ]

    func lowerLegacySequenceIterableSingleArgFallback(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        isSourceBackedTerminalCall: Bool,
        isSourceBackedSequenceCall: Bool,
        loweredReceiverID: KIRExprID,
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.count == 1 else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let useSequenceRuntimeForCollectionFallback = !isSourceBackedTerminalCall
            && !isSourceBackedSequenceCall
            && isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
        let useIterableRuntimeForCollectionFallback = !isSourceBackedTerminalCall
            && !isSourceBackedSequenceCall
            && (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
            && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
        if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
            let runtimeCallee: String?
            switch interner.resolve(calleeName) {
            case "map": runtimeCallee = "kk_sequence_map"
            case "filter": runtimeCallee = "kk_sequence_filter"
            case "takeLast": runtimeCallee = "kk_sequence_takeLast"
            case "flatMap": runtimeCallee = "kk_sequence_flatMap"
            case "flatMapIndexed": runtimeCallee = "kk_sequence_flatMapIndexed"
            case "takeLastWhile": runtimeCallee = "kk_sequence_takeLastWhile"
            case "sortedBy": runtimeCallee = "kk_sequence_sortedBy"
            case "sortedByDescending": runtimeCallee = "kk_sequence_sortedByDescending"
            case "firstNotNullOf": runtimeCallee = "kk_sequence_firstNotNullOf"
            case "firstNotNullOfOrNull": runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
            case "contains": runtimeCallee = "kk_sequence_contains"
            case "indexOf": runtimeCallee = "kk_sequence_indexOf"
            case "indexOfFirst": runtimeCallee = "kk_sequence_indexOfFirst"
            case "lastIndexOf": runtimeCallee = "kk_sequence_lastIndexOf"
            case "indexOfLast": runtimeCallee = "kk_sequence_indexOfLast"
            case "elementAt": runtimeCallee = "kk_sequence_elementAt"
            case "elementAtOrElse": runtimeCallee = "kk_sequence_elementAtOrElse"
            case "elementAtOrNull": runtimeCallee = "kk_sequence_elementAtOrNull"
            case "filterIndexed": runtimeCallee = "kk_sequence_filterIndexed"
            case "last":
                runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_last" : "kk_sequence_last"
            case "min": runtimeCallee = "kk_sequence_min"
            case "max": runtimeCallee = "kk_sequence_max"
            case "any":
                runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_any" : "kk_sequence_any"
            case "all":
                runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_all" : "kk_sequence_all"
            case "none": runtimeCallee = "kk_sequence_none"
            case "mapNotNull": runtimeCallee = "kk_sequence_mapNotNull"
            case "mapIndexedNotNull": runtimeCallee = "kk_sequence_mapIndexedNotNull"
            case "random": runtimeCallee = "kk_sequence_random"
            case "randomOrNull": runtimeCallee = "kk_sequence_randomOrNull"
            case "requireNoNulls": runtimeCallee = "kk_sequence_requireNoNulls"
            case "reversed": runtimeCallee = "kk_sequence_reversed"
            case "mapIndexed": runtimeCallee = "kk_sequence_mapIndexed"
            case "onEach": runtimeCallee = "kk_sequence_onEach"
            case "onEachIndexed": runtimeCallee = "kk_sequence_onEachIndexed"
            case "plus":
                if let firstArg = args.first {
                    let argType = sema.types.makeNonNullable(
                        sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
                    )
                    runtimeCallee = (sema.bindings.isCollectionExpr(firstArg.expr)
                        || isSequenceLikeType(argType, sema: sema, interner: interner)
                        || isIterableOrCollectionInterfaceType(argType, sema: sema, interner: interner)
                        || isConcreteCollectionLikeType(argType, sema: sema, interner: interner))
                        ? "kk_sequence_plus"
                        : "kk_sequence_plus_element"
                } else {
                    runtimeCallee = "kk_sequence_plus_element"
                }
            case "plusElement": runtimeCallee = "kk_sequence_plus_element"
            case "minus", "minusElement": runtimeCallee = "kk_sequence_minus"
            case "reduceOrNull": runtimeCallee = "kk_sequence_reduceOrNull"
            case "reduceRight": runtimeCallee = "kk_sequence_reduceRight"
            case "reduce": runtimeCallee = "kk_sequence_reduce"
            case "runningReduceIndexed": runtimeCallee = "kk_sequence_runningReduceIndexed"
            case "reduceRightIndexed": runtimeCallee = "kk_sequence_reduceRightIndexed"
            case "reduceRightOrNull": runtimeCallee = "kk_sequence_reduceRightOrNull"
            case "reduceRightIndexedOrNull": runtimeCallee = "kk_sequence_reduceRightIndexedOrNull"
            case "shuffled":
                switch normalizedArgIDs.count {
                case 0: runtimeCallee = "kk_sequence_shuffled"
                case 1: runtimeCallee = "kk_sequence_shuffled_random"
                default: runtimeCallee = nil
                }
            case "ifEmpty": runtimeCallee = "kk_sequence_ifEmpty"
            default: runtimeCallee = nil
            }
            if let runtimeCallee {
                let canThrow = Self.throwingSequenceSingleArgCallees.contains(runtimeCallee)
                var runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                if Self.lambdaSplitSequenceSingleArgCallees.contains(runtimeCallee),
                   normalizedArgIDs.count == 1
                {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[0],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                }
                if runtimeCallee == "kk_sequence_elementAtOrElse",
                   normalizedArgIDs.count == 2
                {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    runtimeArguments = [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr]
                }
                instructions.append(.call(callee: interner.intern(runtimeCallee), arguments: runtimeArguments, result: result, canThrow: canThrow))
                return result
            }
        }
        return nil
    }

    func lowerLegacySequenceIterableZeroArgFallback(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        isSourceBackedTerminalCall: Bool,
        isSourceBackedSequenceCall: Bool,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let useSequenceRuntimeForTerminalFallback = !isSourceBackedTerminalCall
            && !isSourceBackedSequenceCall
            && isSequenceLikeType(
                nonNullReceiverType,
                sema: sema,
                interner: interner
            )
        let useIterableRuntimeForTerminalFallback = !isSourceBackedTerminalCall
            && (sema.bindings.isCollectionExpr(receiverExpr)
            || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
            && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
        if useSequenceRuntimeForTerminalFallback || useIterableRuntimeForTerminalFallback {
            let toListID = interner.intern("toList")
            let constrainOnceID = interner.intern("constrainOnce")
            let sortedID = interner.intern("sorted")
            let sortedDescendingID = interner.intern("sortedDescending")
            let filterNotNullID = interner.intern("filterNotNull")
            let requireNoNullsID = interner.intern("requireNoNulls")
            let withIndexID = interner.intern("withIndex")
            let firstID = interner.intern("first")
            let firstOrNullID = interner.intern("firstOrNull")
            let lastID = interner.intern("last")
            let lastOrNullID = interner.intern("lastOrNull")
            let countID = interner.intern("count")
            let sumID = interner.intern("sum")
            let averageID = interner.intern("average")
            let toMutableListID = interner.intern("toMutableList")
            let toMutableSetID = interner.intern("toMutableSet")
            let toSortedSetID = interner.intern("toSortedSet")
            let toHashSetID = interner.intern("toHashSet")
            let unzipID = interner.intern("unzip")
            let anyID = interner.intern("any")
            let noneID = interner.intern("none")

            let seqFirstCallee = interner.intern("kk_sequence_first")
            let seqFirstOrNullCallee = interner.intern("kk_sequence_firstOrNull")
            let seqLastCallee = interner.intern("kk_sequence_last")
            let seqLastOrNullCallee = interner.intern("kk_sequence_lastOrNull")
            let seqSingleCallee = interner.intern("kk_sequence_single")
            let seqSingleOrNullCallee = interner.intern("kk_sequence_singleOrNull")
            let seqCountCallee = interner.intern("kk_sequence_count")
            let seqAnyCallee = interner.intern("kk_sequence_any")
            let seqNoneCallee = interner.intern("kk_sequence_none")
            let seqToListCallee = interner.intern("kk_sequence_to_list")

            let runtimeCallee: InternedString? = switch calleeName {
            case toListID:
                useIterableRuntimeForTerminalFallback
                    ? interner.intern("__kk_collection_toList")
                    : seqToListCallee
            case constrainOnceID:
                interner.intern("kk_sequence_constrainOnce")
            case sortedID:
                interner.intern("kk_sequence_sorted")
            case sortedDescendingID:
                interner.intern("kk_sequence_sortedDescending")
            case interner.intern("shuffled") where args.isEmpty:
                interner.intern("kk_sequence_shuffled")
            case filterNotNullID:
                interner.intern("kk_sequence_filterNotNull")
            case requireNoNullsID:
                interner.intern("kk_sequence_requireNoNulls")
            case withIndexID:
                interner.intern("kk_sequence_withIndex")
            case firstID:
                seqFirstCallee
            case firstOrNullID:
                seqFirstOrNullCallee
            case lastID:
                seqLastCallee
            case lastOrNullID:
                seqLastOrNullCallee
            case interner.intern("single"):
                seqSingleCallee
            case interner.intern("singleOrNull"):
                seqSingleOrNullCallee
            case countID:
                seqCountCallee
            case sumID:
                interner.intern("kk_sequence_sum")
            case averageID:
                interner.intern("kk_sequence_average")
            case toMutableListID:
                toMutableListRuntimeCalleeForSequenceOrIterableFallback(
                    useIterableFallback: useIterableRuntimeForTerminalFallback,
                    interner: interner
                )
            case toMutableSetID:
                interner.intern(useIterableRuntimeForTerminalFallback
                    ? "__kk_iterable_toMutableSet"
                    : "kk_sequence_toMutableSet")
            case toSortedSetID:
                interner.intern("kk_sequence_toSortedSet")
            case toHashSetID:
                interner.intern("kk_sequence_toHashSet")
            case unzipID:
                interner.intern("kk_sequence_unzip")
            case anyID:
                seqAnyCallee
            case noneID:
                seqNoneCallee
            default:
                nil
            }
            if let runtimeCallee {
                // any()/none() with no predicate: pass fnPtr=0, closure=0 sentinel
                if runtimeCallee == seqAnyCallee || runtimeCallee == seqNoneCallee {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: nil)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    instructions.append(.call(
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                        result: result,
                        canThrow: false
                    ))
                    return result
                }
                let canThrow = runtimeCallee == seqFirstCallee
                    || runtimeCallee == seqFirstOrNullCallee
                    || runtimeCallee == seqLastCallee
                    || runtimeCallee == seqLastOrNullCallee
                    || runtimeCallee == seqCountCallee
                    || runtimeCallee == seqToListCallee
                instructions.append(.call(callee: runtimeCallee, arguments: [loweredReceiverID], result: result, canThrow: canThrow))
                return result
            }
        }
        return nil
    }

}
