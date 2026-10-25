extension CallLowerer {

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
            let mapName = interner.intern("map")
            let filterName = interner.intern("filter")
            let flatMapName = interner.intern("flatMap")
            let flatMapIndexedName = interner.intern("flatMapIndexed")
            let takeLastWhileName = interner.intern("takeLastWhile")
            let sortedByName = interner.intern("sortedBy")
            let sortedByDescendingName = interner.intern("sortedByDescending")
            let firstNotNullOfName = interner.intern("firstNotNullOf")
            let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
            let containsName = interner.intern("contains")
            let indexOfName = interner.intern("indexOf")
            let indexOfFirstName = interner.intern("indexOfFirst")
            let lastIndexOfName = interner.intern("lastIndexOf")
            let indexOfLastName = interner.intern("indexOfLast")
            let elementAtName = interner.intern("elementAt")
            let elementAtOrElseName = interner.intern("elementAtOrElse")
            let elementAtOrNullName = interner.intern("elementAtOrNull")
            let filterIndexedName = interner.intern("filterIndexed")
            let lastName = interner.intern("last")
            let minName = interner.intern("min")
            if calleeName == mapName {
                runtimeCallee = "kk_sequence_map"
            } else if calleeName == filterName {
                runtimeCallee = "kk_sequence_filter"
            } else if calleeName == interner.intern("takeLast") {
                runtimeCallee = "kk_sequence_takeLast"
            } else if calleeName == flatMapName {
                runtimeCallee = "kk_sequence_flatMap"
            } else if calleeName == flatMapIndexedName {
                runtimeCallee = "kk_sequence_flatMapIndexed"
            } else if calleeName == takeLastWhileName {
                runtimeCallee = "kk_sequence_takeLastWhile"
            } else if calleeName == sortedByName {
                runtimeCallee = "kk_sequence_sortedBy"
            } else if calleeName == sortedByDescendingName {
                runtimeCallee = "kk_sequence_sortedByDescending"
            } else if calleeName == firstNotNullOfName {
                runtimeCallee = "kk_sequence_firstNotNullOf"
            } else if calleeName == firstNotNullOfOrNullName {
                runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
            } else if calleeName == containsName {
                runtimeCallee = "kk_sequence_contains"
            } else if calleeName == indexOfName {
                runtimeCallee = "kk_sequence_indexOf"
            } else if calleeName == indexOfFirstName {
                runtimeCallee = "kk_sequence_indexOfFirst"
            } else if calleeName == lastIndexOfName {
                runtimeCallee = "kk_sequence_lastIndexOf"
            } else if calleeName == indexOfLastName {
                runtimeCallee = "kk_sequence_indexOfLast"
            } else if calleeName == elementAtName {
                runtimeCallee = "kk_sequence_elementAt"
            } else if calleeName == elementAtOrElseName {
                runtimeCallee = "kk_sequence_elementAtOrElse"
            } else if calleeName == elementAtOrNullName {
                runtimeCallee = "kk_sequence_elementAtOrNull"
            } else if calleeName == interner.intern("elementAtOrElse") {
                runtimeCallee = "kk_sequence_elementAtOrElse"
            } else if calleeName == filterIndexedName {
                runtimeCallee = "kk_sequence_filterIndexed"
            } else if calleeName == lastName {
                runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_last" : "kk_sequence_last"
            } else if calleeName == minName {
                runtimeCallee = "kk_sequence_min"
            } else if calleeName == interner.intern("max") {
                runtimeCallee = "kk_sequence_max"
            } else if calleeName == interner.intern("any") {
                runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_any" : "kk_sequence_any"
            } else if calleeName == interner.intern("all") {
                runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_all" : "kk_sequence_all"
            } else if calleeName == interner.intern("none") {
                runtimeCallee = "kk_sequence_none"
            } else if calleeName == interner.intern("mapNotNull") {
                runtimeCallee = "kk_sequence_mapNotNull"
            } else if calleeName == interner.intern("mapIndexedNotNull") {
                runtimeCallee = "kk_sequence_mapIndexedNotNull"
            } else if calleeName == interner.intern("firstNotNullOf") {
                runtimeCallee = "kk_sequence_firstNotNullOf"
            } else if calleeName == interner.intern("firstNotNullOfOrNull") {
                runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
            } else if calleeName == interner.intern("random") {
                runtimeCallee = "kk_sequence_random"
            } else if calleeName == interner.intern("randomOrNull") {
                runtimeCallee = "kk_sequence_randomOrNull"
            } else if calleeName == interner.intern("requireNoNulls") {
                runtimeCallee = "kk_sequence_requireNoNulls"
            } else if calleeName == interner.intern("reversed") {
                runtimeCallee = "kk_sequence_reversed"
            } else if calleeName == interner.intern("mapIndexed") {
                runtimeCallee = "kk_sequence_mapIndexed"
            } else if calleeName == interner.intern("flatMapIndexed") {
                runtimeCallee = "kk_sequence_flatMapIndexed"
            } else if calleeName == interner.intern("onEach") {
                runtimeCallee = "kk_sequence_onEach"
            } else if calleeName == interner.intern("onEachIndexed") {
                runtimeCallee = "kk_sequence_onEachIndexed"
            } else if calleeName == interner.intern("plus") {
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
            } else if calleeName == interner.intern("plusElement") {
                runtimeCallee = "kk_sequence_plus_element"
            } else if calleeName == interner.intern("minus") || calleeName == interner.intern("minusElement") {
                runtimeCallee = "kk_sequence_minus"
            } else if calleeName == interner.intern("reduceOrNull") {
                runtimeCallee = "kk_sequence_reduceOrNull"
            } else if calleeName == interner.intern("reduceRight") {
                runtimeCallee = "kk_sequence_reduceRight"
            } else if calleeName == interner.intern("reduce") {
                runtimeCallee = "kk_sequence_reduce"
            } else if calleeName == interner.intern("runningReduceIndexed") {
                runtimeCallee = "kk_sequence_runningReduceIndexed"
            } else if calleeName == interner.intern("reduceRightIndexed") {
                runtimeCallee = "kk_sequence_reduceRightIndexed"
            } else if calleeName == interner.intern("reduceRightOrNull") {
                runtimeCallee = "kk_sequence_reduceRightOrNull"
            } else if calleeName == interner.intern("reduceRightIndexedOrNull") {
                runtimeCallee = "kk_sequence_reduceRightIndexedOrNull"
            } else if calleeName == interner.intern("shuffled") {
                switch normalizedArgIDs.count {
                case 0: runtimeCallee = "kk_sequence_shuffled"
                case 1: runtimeCallee = "kk_sequence_shuffled_random"
                default: runtimeCallee = nil
                }
            } else if calleeName == interner.intern("ifEmpty") {
                runtimeCallee = "kk_sequence_ifEmpty"
            } else {
                runtimeCallee = nil
            }
            if let runtimeCallee {
                let canThrow = runtimeCallee == "kk_sequence_sortedBy"
                    || runtimeCallee == "kk_sequence_sortedByDescending"
                    || runtimeCallee == "kk_sequence_takeLastWhile"
                    || runtimeCallee == "kk_sequence_firstNotNullOf"
                    || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                    || runtimeCallee == "kk_sequence_takeLast"
                    || runtimeCallee == "kk_sequence_elementAt"
                    || runtimeCallee == "kk_sequence_elementAtOrElse"
                    || runtimeCallee == "kk_sequence_last"
                    || runtimeCallee == "__kk_iterable_last"
                    || runtimeCallee == "kk_sequence_min"
                    || runtimeCallee == "kk_sequence_max"
                    || runtimeCallee == "kk_sequence_any"
                    || runtimeCallee == "__kk_iterable_any"
                    || runtimeCallee == "kk_sequence_all"
                    || runtimeCallee == "__kk_iterable_all"
                    || runtimeCallee == "kk_sequence_none"
                    || runtimeCallee == "kk_sequence_indexOfFirst"
                    || runtimeCallee == "kk_sequence_indexOfLast"
                    || runtimeCallee == "kk_sequence_mapNotNull"
                    || runtimeCallee == "kk_sequence_mapIndexedNotNull"
                    || runtimeCallee == "kk_sequence_firstNotNullOf"
                    || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                    || runtimeCallee == "kk_sequence_random"
                    || runtimeCallee == "kk_sequence_randomOrNull"
                    || runtimeCallee == "kk_sequence_mapIndexed"
                    || runtimeCallee == "kk_sequence_filterIndexed"
                    || runtimeCallee == "kk_sequence_onEach"
                    || runtimeCallee == "kk_sequence_onEachIndexed"
                    || runtimeCallee == "kk_sequence_reduceOrNull"
                    || runtimeCallee == "kk_sequence_reduce"
                    || runtimeCallee == "kk_sequence_reduceRightIndexed"
                    || runtimeCallee == "kk_sequence_reduceRight"
                    || runtimeCallee == "kk_sequence_reduceRightOrNull"
                    || runtimeCallee == "kk_sequence_reduceRightIndexedOrNull"
                    || runtimeCallee == "kk_sequence_runningReduceIndexed"
                    || runtimeCallee == "kk_sequence_ifEmpty"
                var runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                if runtimeCallee == "kk_sequence_firstNotNullOf"
                    || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                    || runtimeCallee == "kk_sequence_takeLastWhile",
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
                if runtimeCallee == "kk_sequence_reduceOrNull",
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
                if runtimeCallee == "kk_sequence_indexOfFirst"
                    || runtimeCallee == "kk_sequence_reduceRightIndexed"
                    || runtimeCallee == "kk_sequence_reduceRightOrNull",
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
                if runtimeCallee == "kk_sequence_indexOfLast",
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
                if runtimeCallee == "kk_sequence_reduceRight",
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
                if runtimeCallee == "kk_sequence_reduceRightOrNull",
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
                if runtimeCallee == "kk_sequence_reduce", normalizedArgIDs.count == 1 {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[0],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                }
                if runtimeCallee == "kk_sequence_reduceRightIndexedOrNull",
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
                instructions.append(.call(
                    callee: interner.intern(runtimeCallee),
                    arguments: runtimeArguments,
                    result: result,
                    canThrow: canThrow
                ))
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
                instructions.append(.call(
                    callee: runtimeCallee,
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: canThrow
                ))
                return result
            }
        }
        return nil
    }

}
