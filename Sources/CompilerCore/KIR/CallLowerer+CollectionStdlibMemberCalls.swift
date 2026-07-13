// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallLowerer {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func tryLowerCollectionStdlibMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        requireNonNullableReceiverForConstFold: Bool,
        chosenBase64Callee: SymbolID?,
        boundType: TypeID?,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeText = interner.resolve(calleeName)
        if [
            "associate",
            "associateBy",
            "groupBy",
            "sumOf",
            "maxByOrNull",
            "minByOrNull",
        ].contains(calleeText),
            let chosenBase64Callee,
            sema.symbols.symbol(chosenBase64Callee)?.declSite != nil,
            (sema.symbols.externalLinkName(for: chosenBase64Callee) ?? "").isEmpty
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                return nil
            }
        }

        // any/none 0-arg
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString? = switch interner.resolve(calleeName) {
            case "any":
                if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_array_any")
                } else if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_set_any")
                } else if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_list_any")
                } else {
                    nil
                }
            case "none":
                if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_array_none")
                } else if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_set_none")
                } else if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    interner.intern("kk_list_none")
                } else {
                    nil
                }
            default:
                nil
            }
            if let runtimeCallee {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Sequence joinTo (STDLIB-SEQ-FN-052): buffer plus separator/prefix/postfix defaults.
        if (1 ... 4).contains(args.count), interner.resolve(calleeName) == "joinTo" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let stringType = sema.types.stringType
                let paramNames = ["buffer", "separator", "prefix", "postfix"]
                let defaults = [nil, ", ", "", ""]
                var resolved: [KIRExprID?] = [nil, nil, nil, nil]
                for (argIdx, arg) in args.enumerated() {
                    if let label = arg.label,
                       let paramIdx = paramNames.firstIndex(of: interner.resolve(label))
                    {
                        resolved[paramIdx] = loweredArgIDs[argIdx]
                    } else if let slot = resolved.firstIndex(where: { $0 == nil }), slot <= argIdx {
                        resolved[slot] = loweredArgIDs[argIdx]
                    } else {
                        resolved[argIdx] = loweredArgIDs[argIdx]
                    }
                }
                if let destinationArg = resolved[0] {
                    var joinArgs: [KIRExprID] = [destinationArg]
                    for paramIndex in 1 ..< 4 {
                        if let existing = resolved[paramIndex] {
                            joinArgs.append(existing)
                        } else if let defaultValue = defaults[paramIndex] {
                            let interned = interner.intern(defaultValue)
                            let exprID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                            instructions.append(.constValue(result: exprID, value: .stringLiteral(interned)))
                            joinArgs.append(exprID)
                        }
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_sequence_joinTo"),
                        arguments: [loweredReceiverID] + joinArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Sequence joinToString (STDLIB-275): 0-3 args, non-HOF, non-throwing
        if args.count <= 3, interner.resolve(calleeName) == "joinToString" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let stringType = sema.types.stringType
                let paramNames = ["separator", "prefix", "postfix"]
                let defaults = [", ", "", ""]
                // Build a 3-element array mapping each parameter to its lowered arg or a default
                var resolved: [KIRExprID?] = [nil, nil, nil]
                for (argIdx, arg) in args.enumerated() {
                    if let label = arg.label,
                       let paramIdx = paramNames.firstIndex(of: interner.resolve(label))
                    {
                        resolved[paramIdx] = loweredArgIDs[argIdx]
                    } else {
                        // Positional argument: fill first unresolved slot
                        if let slot = resolved.firstIndex(where: { $0 == nil }), slot <= argIdx {
                            resolved[slot] = loweredArgIDs[argIdx]
                        } else {
                            resolved[argIdx] = loweredArgIDs[argIdx]
                        }
                    }
                }
                var joinArgs: [KIRExprID] = []
                for paramIndex in 0 ..< 3 {
                    if let existing = resolved[paramIndex] {
                        joinArgs.append(existing)
                    } else {
                        let interned = interner.intern(defaults[paramIndex])
                        let exprID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                        instructions.append(.constValue(result: exprID, value: .stringLiteral(interned)))
                        joinArgs.append(exprID)
                    }
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_joinToString"),
                    arguments: [loweredReceiverID] + joinArgs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 1,
           calleeName == interner.intern("plusElement") || calleeName == interner.intern("minusElement")
               || calleeName == interner.intern("minus")
        {
            let chosenLinkName = chosenBase64Callee.flatMap { sema.symbols.externalLinkName(for: $0) }
            let returnsList = boundType.map { resultType in
                guard let (_, resultSymbol) = resolveClassTypeSymbol(resultType, sema: sema)
                else { return false }
                return interner.resolve(resultSymbol.name) == "List"
            } ?? false
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let receiverIsIterable = {
                guard let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                else { return false }
                return receiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Iterable"),
                ]
            }()
            let isPlusCallee = calleeName == interner.intern("plusElement")
            let isMinusCallee = calleeName == interner.intern("minusElement")
                || calleeName == interner.intern("minus")
            let runtimeCallee = isPlusCallee
                ? "kk_list_plus_element"
                : "kk_list_minus_element"
            // For `minus`, check whether the argument is itself a collection (List/Set/Array).
            // If so, route to kk_list_minus_collection rather than kk_list_minus_element.
            let argIsCollection: Bool
            if calleeName == interner.intern("minus"), let firstArgExpr = args.first?.expr {
                let argType = sema.bindings.exprTypes[firstArgExpr] ?? sema.types.anyType
                let nonNullArgType = sema.types.makeNonNullable(argType)
                argIsCollection = isConcreteListLikeType(nonNullArgType, sema: sema, interner: interner)
                    || isSetLikeType(nonNullArgType, sema: sema, interner: interner)
                    || isConcreteArrayLikeType(nonNullArgType, sema: sema, interner: interner)
            } else {
                argIsCollection = false
            }
            // When `minus` has a collection argument, dispatch to kk_list_minus_collection.
            if isMinusCallee && argIsCollection {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_minus_collection"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // `returnsList` is not safe for `minus` because collection-minus overloads
            // (e.g. Iterable<T>.minus(elements: Iterable<T>)) also return List<T>.
            let listReturnFallback = calleeName != interner.intern("minus") && returnsList
            if (isPlusCallee || isMinusCallee),
               chosenLinkName == runtimeCallee || listReturnFallback || receiverIsIterable
            {
                instructions.append(.call(
                    symbol: chosenBase64Callee,
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "get" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get"),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "contains" {
                    let listExpr = arena.appendTemporary(type: nil)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_toList"),
                        arguments: [loweredReceiverID],
                        result: listExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_list_contains"),
                        arguments: [listExpr] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let runtimeCallee: String? = switch calleeStr {
                case "map":
                    "kk_array_map"
                case "filter":
                    "kk_array_filter"
                case "forEach":
                    "kk_array_forEach"
                case "any":
                    "kk_array_any"
                case "all":
                    "kk_array_all"
                case "none":
                    "kk_array_none"
                case "count":
                    "kk_array_count"
                case "fill":
                    "kk_array_fill"
                case "firstNotNullOf":
                    "kk_iterable_firstNotNullOf"
                case "firstNotNullOfOrNull":
                    "kk_iterable_firstNotNullOfOrNull"
                case "reduce":
                    "kk_array_reduce"
                case "reduceOrNull":
                    "kk_array_reduceOrNull"
                case "reduceIndexed":
                    "kk_array_reduceIndexed"
                case "fold":
                    "kk_array_fold"
                case "foldIndexed":
                    "kk_array_foldIndexed"
                case "flatMap":
                    "kk_array_flatMap"
                default:
                    nil
                }
                if let runtimeCallee {
                    let canThrow = runtimeCallee == "kk_list_partition"
                        || runtimeCallee == "kk_iterable_firstNotNullOf"
                        || runtimeCallee == "kk_iterable_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_array_reduce"
                        || runtimeCallee == "kk_array_reduceOrNull"
                        || runtimeCallee == "kk_array_reduceIndexed"
                        || runtimeCallee == "kk_array_fold"
                        || runtimeCallee == "kk_array_foldIndexed"
                        || runtimeCallee == "kk_array_flatMap"
                    let thrownResult = canThrow
                        ? arena.appendTemporary(type: sema.types.nullableAnyType
                        )
                        : nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForCollectionFallback = isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
            let useIterableRuntimeForCollectionFallback = (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
                let runtimeCallee: String?
                let mapName = interner.intern("map")
                let filterName = interner.intern("filter")
                let takeName = interner.intern("take")
                let forEachName = interner.intern("forEach")
                let flatMapName = interner.intern("flatMap")
                let flatMapToName = interner.intern("flatMapTo")
                let flatMapIndexedName = interner.intern("flatMapIndexed")
                let dropName = interner.intern("drop")
                let zipName = interner.intern("zip")
                let takeWhileName = interner.intern("takeWhile")
                let takeLastWhileName = interner.intern("takeLastWhile")
                let dropWhileName = interner.intern("dropWhile")
                let sortedByName = interner.intern("sortedBy")
                let sortedWithName = interner.intern("sortedWith")
                let sortedByDescendingName = interner.intern("sortedByDescending")
                let sumOfName = interner.intern("sumOf")
                let sumByName = interner.intern("sumBy")
                let sumByDoubleName = interner.intern("sumByDouble")
                let firstNotNullOfName = interner.intern("firstNotNullOf")
                let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
                let associateName = interner.intern("associate")
                let associateByName = interner.intern("associateBy")
                let associateWithName = interner.intern("associateWith")
                let associateToName = interner.intern("associateTo")
                let associateByToName = interner.intern("associateByTo")
                let associateWithToName = interner.intern("associateWithTo")
                let groupByToName = interner.intern("groupByTo")
                let flatMapIndexedToName = interner.intern("flatMapIndexedTo")
                let containsName = interner.intern("contains")
                let indexOfName = interner.intern("indexOf")
                let indexOfFirstName = interner.intern("indexOfFirst")
                let lastIndexOfName = interner.intern("lastIndexOf")
                let indexOfLastName = interner.intern("indexOfLast")
                let elementAtName = interner.intern("elementAt")
                let elementAtOrElseName = interner.intern("elementAtOrElse")
                let elementAtOrNullName = interner.intern("elementAtOrNull")
                let filterIndexedName = interner.intern("filterIndexed")
                let findLastName = interner.intern("findLast")
                let lastName = interner.intern("last")
                let partitionName = interner.intern("partition")
                let minByName = interner.intern("minBy")
                let minName = interner.intern("min")
                let minByOrNullName = interner.intern("minByOrNull")
                let maxByOrNullName = interner.intern("maxByOrNull")
                let minOfName = interner.intern("minOf")
                let minWithName = interner.intern("minWith")
                let minOfOrNullName = interner.intern("minOfOrNull")
                let maxOfName = interner.intern("maxOf")
                let distinctByName = interner.intern("distinctBy")
                if calleeName == mapName {
                    runtimeCallee = "kk_sequence_map"
                } else if calleeName == filterName {
                    runtimeCallee = "kk_sequence_filter"
                } else if calleeName == takeName {
                    runtimeCallee = "kk_sequence_take"
                } else if calleeName == interner.intern("takeLast") {
                    runtimeCallee = "kk_sequence_takeLast"
                } else if calleeName == forEachName {
                    runtimeCallee = "kk_sequence_forEach"
                } else if calleeName == flatMapName {
                    runtimeCallee = "kk_sequence_flatMap"
                } else if calleeName == flatMapToName {
                    runtimeCallee = "kk_sequence_flatMapTo"
                } else if calleeName == flatMapIndexedName {
                    runtimeCallee = "kk_sequence_flatMapIndexed"
                } else if calleeName == dropName {
                    runtimeCallee = "kk_sequence_drop"
                } else if calleeName == zipName {
                    switch normalizedArgIDs.count {
                    case 1: runtimeCallee = "kk_sequence_zip"
                    case 2: runtimeCallee = "kk_sequence_zip_transform"
                    default: runtimeCallee = nil
                    }
                } else if calleeName == takeWhileName {
                    runtimeCallee = "kk_sequence_takeWhile"
                } else if calleeName == takeLastWhileName {
                    runtimeCallee = "kk_sequence_takeLastWhile"
                } else if calleeName == dropWhileName {
                    runtimeCallee = "kk_sequence_dropWhile"
                } else if calleeName == sortedByName {
                    runtimeCallee = "kk_sequence_sortedBy"
                } else if calleeName == sortedWithName {
                    runtimeCallee = "kk_sequence_sortedWith"
                } else if calleeName == sortedByDescendingName {
                    runtimeCallee = "kk_sequence_sortedByDescending"
                } else if calleeName == distinctByName {
                    runtimeCallee = "kk_sequence_distinctBy"
                } else if calleeName == sumOfName {
                    runtimeCallee = "kk_sequence_sumOf"
                } else if calleeName == sumByName {
                    runtimeCallee = "kk_sequence_sumBy"
                } else if calleeName == sumByDoubleName {
                    runtimeCallee = "kk_sequence_sumByDouble"
                } else if calleeName == firstNotNullOfName {
                    runtimeCallee = "kk_sequence_firstNotNullOf"
                } else if calleeName == firstNotNullOfOrNullName {
                    runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
                } else if calleeName == associateName {
                    runtimeCallee = "kk_sequence_associate"
                } else if calleeName == associateByName {
                    runtimeCallee = "kk_sequence_associateBy"
                } else if calleeName == associateWithName {
                    runtimeCallee = "kk_sequence_associateWith"
                } else if calleeName == associateToName {
                    runtimeCallee = "kk_sequence_associateTo"
                } else if calleeName == associateByToName {
                    runtimeCallee = "kk_sequence_associateByTo"
                } else if calleeName == associateWithToName {
                    runtimeCallee = "kk_sequence_associateWithTo"
                } else if calleeName == groupByToName {
                    runtimeCallee = "kk_sequence_groupByTo"
                } else if calleeName == flatMapIndexedToName {
                    runtimeCallee = "kk_sequence_flatMapIndexedTo"
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
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "kk_iterable_last" : "kk_sequence_last"
                } else if calleeName == findLastName {
                    runtimeCallee = "kk_sequence_findLast"
                } else if calleeName == partitionName {
                    runtimeCallee = "kk_sequence_partition"
                } else if calleeName == minByName {
                    runtimeCallee = "kk_sequence_minBy"
                } else if calleeName == minName {
                    runtimeCallee = "kk_sequence_min"
                } else if calleeName == interner.intern("maxBy") {
                    runtimeCallee = "kk_sequence_maxBy"
                } else if calleeName == minByOrNullName {
                    runtimeCallee = "kk_sequence_minByOrNull"
                } else if calleeName == maxByOrNullName {
                    runtimeCallee = "kk_sequence_maxByOrNull"
                } else if calleeName == interner.intern("maxWith") {
                    runtimeCallee = "kk_sequence_maxWith"
                } else if calleeName == interner.intern("maxWithOrNull") {
                    runtimeCallee = "kk_sequence_maxWithOrNull"
                } else if calleeName == minOfName {
                    runtimeCallee = "kk_sequence_minOf"
                } else if calleeName == minOfOrNullName {
                    runtimeCallee = "kk_sequence_minOfOrNull"
                } else if calleeName == interner.intern("maxOfOrNull") {
                    runtimeCallee = "kk_sequence_maxOfOrNull"
                } else if calleeName == interner.intern("minWithOrNull") {
                    runtimeCallee = "kk_sequence_minWithOrNull"
                } else if calleeName == minWithName {
                    runtimeCallee = "kk_sequence_minWith"
                } else if calleeName == maxOfName {
                    runtimeCallee = "kk_sequence_maxOf"
                } else if calleeName == interner.intern("max") {
                    runtimeCallee = "kk_sequence_max"
                } else if calleeName == interner.intern("find") {
                    runtimeCallee = "kk_sequence_find"
                } else if calleeName == interner.intern("findLast") {
                    runtimeCallee = "kk_sequence_findLast"
                } else if calleeName == interner.intern("intersect") {
                    runtimeCallee = "kk_sequence_intersect"
                } else if calleeName == interner.intern("any") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "kk_iterable_any" : "kk_sequence_any"
                } else if calleeName == interner.intern("all") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "kk_iterable_all" : "kk_sequence_all"
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
                } else if calleeName == interner.intern("windowed"), args.count == 4 {
                    runtimeCallee = "kk_sequence_windowed_transform"
                } else if calleeName == interner.intern("chunked") {
                    runtimeCallee = args.count == 2
                        ? "kk_sequence_chunked_transform"
                        : "kk_sequence_chunked"
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
                } else if calleeName == interner.intern("union") {
                    runtimeCallee = "kk_sequence_union"
                } else if calleeName == interner.intern("subtract") {
                    runtimeCallee = "kk_sequence_subtract"
                } else if calleeName == interner.intern("reduceRight") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback
                        ? "kk_list_reduceRight"
                        : "kk_sequence_reduceRight"
                } else if calleeName == interner.intern("reduce") {
                    runtimeCallee = "kk_sequence_reduce"
                } else if calleeName == interner.intern("runningReduceIndexed") {
                    runtimeCallee = "kk_sequence_runningReduceIndexed"
                } else if calleeName == interner.intern("reduceRightIndexed") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback
                        ? "kk_list_reduceRightIndexed"
                        : "kk_sequence_reduceRightIndexed"
                } else if calleeName == interner.intern("reduceRightOrNull") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback
                        ? "kk_list_reduceRightOrNull"
                        : "kk_sequence_reduceRightOrNull"
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
                } else if calleeName == interner.intern("forEachIndexed") {
                    runtimeCallee = "kk_sequence_forEachIndexed"
                } else if calleeName == interner.intern("zipWithNext") {
                    // Overload dispatch: no-arg → kk_sequence_zipWithNext, with transform → kk_sequence_zipWithNextTransform
                    runtimeCallee = normalizedArgIDs.isEmpty ? "kk_sequence_zipWithNext" : "kk_sequence_zipWithNextTransform"
                } else {
                    runtimeCallee = nil
                }
                if let runtimeCallee {
                    let canThrow = runtimeCallee == "kk_sequence_sortedBy"
                        || runtimeCallee == "kk_sequence_sortedWith"
                        || runtimeCallee == "kk_sequence_sortedByDescending"
                        || runtimeCallee == "kk_sequence_distinctBy"
                        || runtimeCallee == "kk_sequence_sumOf"
                        || runtimeCallee == "kk_sequence_sumBy"
                        || runtimeCallee == "kk_sequence_sumByDouble"
                        || runtimeCallee == "kk_sequence_takeLastWhile"
                        || runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_associate"
                        || runtimeCallee == "kk_sequence_associateBy"
                        || runtimeCallee == "kk_sequence_associateTo"
                        || runtimeCallee == "kk_sequence_associateByTo"
                        || runtimeCallee == "kk_sequence_associateWithTo"
                        || runtimeCallee == "kk_sequence_associateWith"
                        || runtimeCallee == "kk_sequence_groupByTo"
                        || runtimeCallee == "kk_sequence_flatMapIndexedTo"
                        || runtimeCallee == "kk_sequence_flatMapTo"
                        || runtimeCallee == "kk_sequence_find"
                        || runtimeCallee == "kk_sequence_findLast"
                        || runtimeCallee == "kk_sequence_takeLast"
                        || runtimeCallee == "kk_sequence_elementAt"
                        || runtimeCallee == "kk_sequence_elementAtOrElse"
                        || runtimeCallee == "kk_sequence_last"
                        || runtimeCallee == "kk_iterable_last"
                        || runtimeCallee == "kk_sequence_minBy"
                        || runtimeCallee == "kk_sequence_min"
                        || runtimeCallee == "kk_sequence_maxBy"
                        || runtimeCallee == "kk_sequence_minByOrNull"
                        || runtimeCallee == "kk_sequence_maxByOrNull"
                        || runtimeCallee == "kk_sequence_maxWith"
                        || runtimeCallee == "kk_sequence_maxWithOrNull"
                        || runtimeCallee == "kk_sequence_minOf"
                        || runtimeCallee == "kk_sequence_minOfOrNull"
                        || runtimeCallee == "kk_sequence_maxOfOrNull"
                        || runtimeCallee == "kk_sequence_minWithOrNull"
                        || runtimeCallee == "kk_sequence_minWith"
                        || runtimeCallee == "kk_sequence_maxOf"
                        || runtimeCallee == "kk_sequence_max"
                        || runtimeCallee == "kk_sequence_partition"
                        || runtimeCallee == "kk_sequence_any"
                        || runtimeCallee == "kk_iterable_any"
                        || runtimeCallee == "kk_sequence_all"
                        || runtimeCallee == "kk_iterable_all"
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
                        || runtimeCallee == "kk_sequence_chunked_transform"
                        || runtimeCallee == "kk_sequence_windowed_transform"
                        || runtimeCallee == "kk_sequence_onEach"
                        || runtimeCallee == "kk_sequence_onEachIndexed"
                        || runtimeCallee == "kk_sequence_reduceOrNull"
                        || runtimeCallee == "kk_sequence_reduce"
                        || runtimeCallee == "kk_sequence_reduceRightIndexed"
                        || runtimeCallee == "kk_list_reduceRightIndexed"
                        || runtimeCallee == "kk_sequence_reduceRight"
                        || runtimeCallee == "kk_sequence_reduceRightOrNull"
                        || runtimeCallee == "kk_list_reduceRightOrNull"
                        || runtimeCallee == "kk_sequence_reduceRightIndexedOrNull"
                        || runtimeCallee == "kk_sequence_runningReduceIndexed"
                        || runtimeCallee == "kk_sequence_ifEmpty"
                        || runtimeCallee == "kk_sequence_zipWithNextTransform"
                        || runtimeCallee == "kk_sequence_zip_transform"
                    var runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                    if runtimeCallee == "kk_sequence_sumOf"
                        || runtimeCallee == "kk_sequence_sumBy"
                        || runtimeCallee == "kk_sequence_sumByDouble",
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
                    if runtimeCallee == "kk_sequence_maxWith"
                        || runtimeCallee == "kk_sequence_maxWithOrNull",
                       normalizedArgIDs.count == 2
                    {
                        runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                    }
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
                    if runtimeCallee == "kk_sequence_zip_transform",
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
                    if runtimeCallee == "kk_sequence_reduceOrNull"
                        || runtimeCallee == "kk_sequence_associate"
                        || runtimeCallee == "kk_sequence_associateBy"
                        || runtimeCallee == "kk_sequence_associateWith",
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
                        || runtimeCallee == "kk_list_reduceRightIndexed"
                        || runtimeCallee == "kk_sequence_reduceRightOrNull"
                        || runtimeCallee == "kk_list_reduceRightOrNull",
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
                    if runtimeCallee == "kk_sequence_reduceRight" || runtimeCallee == "kk_list_reduceRight",
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
                    if runtimeCallee == "kk_sequence_associateTo"
                        || runtimeCallee == "kk_sequence_associateByTo"
                        || runtimeCallee == "kk_sequence_associateWithTo"
                        || runtimeCallee == "kk_sequence_groupByTo"
                        || runtimeCallee == "kk_sequence_flatMapIndexedTo",
                       normalizedArgIDs.count == 2
                    {
                        let firstArg = normalizedArgIDs[0]
                        let secondArg = normalizedArgIDs[1]
                        let lambdaArg: KIRExprID
                        let destinationArg: KIRExprID
                        if args.count >= 2,
                           sema.bindings.isCollectionHOFLambdaExpr(args[0].expr)
                        {
                            lambdaArg = firstArg
                            destinationArg = secondArg
                        } else if args.count >= 2,
                                  sema.bindings.isCollectionHOFLambdaExpr(args[1].expr)
                        {
                            destinationArg = firstArg
                            lambdaArg = secondArg
                        } else if driver.ctx.callableValueInfo(for: firstArg) != nil {
                            lambdaArg = firstArg
                            destinationArg = secondArg
                        } else {
                            destinationArg = firstArg
                            lambdaArg = secondArg
                        }
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            lambdaArg,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, destinationArg, fnPtrExpr, envPtrExpr]
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
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: runtimeArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let primitiveSelectorKind = collectionSelectorPrimitiveCompareKind(of: args.first?.expr, sema: sema)
                let runtimeCallee: String? = switch calleeStr {
                case "sortedBy":
                    primitiveSelectorKind != nil ? "kk_list_sortedBy_primitive" : "kk_list_sortedBy"
                case "sortedByDescending":
                    primitiveSelectorKind != nil ? "kk_list_sortedByDescending_primitive" : "kk_list_sortedByDescending"
                case "distinctBy":
                    "kk_list_distinctBy"
                case "dropLastWhile":
                    "kk_list_dropLastWhile"
                case "sortedWith":
                    "kk_list_sortedWith"
                case "maxOf":
                    "kk_list_maxOf"
                case "minOf":
                    "kk_list_minOf"
                case "max":
                    "kk_list_max"
                case "min":
                    "kk_list_min"
                case "maxWith":
                    "kk_list_maxWith"
                case "maxWithOrNull":
                    "kk_list_maxWithOrNull"
                case "minWith":
                    "kk_list_minWith"
                case "minWithOrNull":
                    "kk_list_minWithOrNull"
                case "maxOfWith":
                    "kk_list_maxOfWith"
                case "maxOfWithOrNull":
                    "kk_list_maxOfWithOrNull"
                case "minOfWith":
                    "kk_list_minOfWith"
                case "minOfWithOrNull":
                    "kk_list_minOfWithOrNull"
                case "minBy":
                    "kk_list_minBy"
                case "indexOf":
                    "kk_list_indexOf"
                case "lastIndexOf":
                    "kk_list_lastIndexOf"
                case "partition":
                    "kk_list_partition"
                case "getOrNull":
                    "kk_list_getOrNull"
                case "elementAtOrNull":
                    "kk_list_elementAtOrNull"
                case "elementAt":
                    "kk_list_elementAt"
                case "containsAll":
                    "kk_list_containsAll"
                case "intersect":
                    "kk_list_intersect"
                default:
                    nil
                }
                if let runtimeCallee {
                    var callArguments = [loweredReceiverID] + normalizedArgIDs
                    if let primitiveSelectorKind,
                       runtimeCallee == "kk_list_sortedBy_primitive" || runtimeCallee == "kk_list_sortedByDescending_primitive"
                    {
                        let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveSelectorKind.rawValue)), type: sema.types.intType)
                        instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveSelectorKind.rawValue))))
                        callArguments.append(kindExpr)
                    }
                    let canThrow = runtimeCallee == "kk_list_elementAt"
                        || runtimeCallee == "kk_list_distinctBy"
                        || runtimeCallee == "kk_list_dropLastWhile"
                        || runtimeCallee == "kk_list_minBy"
                        || runtimeCallee == "kk_list_min"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let runtimeCallee: String? = switch calleeStr {
                case "find":
                    "kk_regex_find"
                case "findAll":
                    "kk_regex_findAll"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "copyOf"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_copyOf_newSize"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                if interner.resolve(calleeName) == "copyOf" {
                    let fnPtrExpr: KIRExprID
                    let envPtrExpr: KIRExprID
                    if normalizedArgIDs.count >= 3 {
                        fnPtrExpr = normalizedArgIDs[1]
                        envPtrExpr = normalizedArgIDs[2]
                    } else {
                        let split = splitCallableLambdaArgument(
                            normalizedArgIDs[1],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        fnPtrExpr = split.fnPtrExpr
                        envPtrExpr = split.envPtrExpr
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_copyOf_newSize_init"),
                        arguments: [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if interner.resolve(calleeName) == "copyOfRange" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_copyOfRange"),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: true,
                        thrownResult: arena.appendTemporary(type: sema.types.nullableAnyType
                        )
                    ))
                    return result
                }
            }
            // List.elementAtOrElse(index, defaultValue) — 2 args (STDLIB-214)
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "elementAtOrElse"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_elementAtOrElse"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        let hasHOFLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false

        // KSP-307: ListWindowChunk public functions are source-backed, but codegen
        // still lowers their executable path to private runtime bridges.
        do {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isListWindowChunkReceiver = isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || isSetLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner)
                || isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner)

            if isListWindowChunkReceiver {
                func appendBridgeCall(
                    _ name: String,
                    _ runtimeArguments: [KIRExprID],
                    canThrow: Bool = false
                ) -> KIRExprID {
                    let thrownResult = canThrow ? arena.appendTemporary(type: sema.types.nullableAnyType) : nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: runtimeArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return result
                }

                func intLiteral(_ value: Int64) -> KIRExprID {
                    let expr = arena.appendExpr(.intLiteral(value), type: sema.types.intType)
                    instructions.append(.constValue(result: expr, value: .intLiteral(value)))
                    return expr
                }

                func windowedTransformRuntimeArguments() -> [KIRExprID]? {
                    guard hasHOFLambdaArg else {
                        return nil
                    }
                    let valueArgCount = args.count - 1
                    guard (1...3).contains(valueArgCount),
                          normalizedArgIDs.count > valueArgCount
                    else {
                        return nil
                    }

                    let sizeArg = normalizedArgIDs[0]
                    let stepArg = valueArgCount >= 2 ? normalizedArgIDs[1] : intLiteral(1)
                    let partialArg = valueArgCount >= 3 ? normalizedArgIDs[2] : intLiteral(0)
                    let fnPtrExpr: KIRExprID
                    let envPtrExpr: KIRExprID
                    if normalizedArgIDs.count > valueArgCount + 1 {
                        fnPtrExpr = normalizedArgIDs[valueArgCount]
                        envPtrExpr = normalizedArgIDs[valueArgCount + 1]
                    } else {
                        let split = splitCallableLambdaArgument(
                            normalizedArgIDs[valueArgCount],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        fnPtrExpr = split.fnPtrExpr
                        envPtrExpr = split.envPtrExpr
                    }
                    return [loweredReceiverID, sizeArg, stepArg, partialArg, fnPtrExpr, envPtrExpr]
                }

                switch interner.resolve(calleeName) {
                case "chunked" where !hasHOFLambdaArg && normalizedArgIDs.count == 1:
                    return appendBridgeCall("__kk_list_chunked", [loweredReceiverID, normalizedArgIDs[0]])
                case "chunked" where hasHOFLambdaArg && normalizedArgIDs.count == 2:
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return appendBridgeCall(
                        "__kk_list_chunked_transform",
                        [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr],
                        canThrow: true
                    )
                case "windowed" where !hasHOFLambdaArg && (1...3).contains(normalizedArgIDs.count):
                    let sizeArg = normalizedArgIDs[0]
                    let stepArg = normalizedArgIDs.count >= 2 ? normalizedArgIDs[1] : intLiteral(1)
                    let partialArg = normalizedArgIDs.count >= 3 ? normalizedArgIDs[2] : intLiteral(0)
                    return appendBridgeCall("__kk_list_windowed", [loweredReceiverID, sizeArg, stepArg, partialArg])
                case "windowed" where hasHOFLambdaArg:
                    guard let runtimeArguments = windowedTransformRuntimeArguments() else {
                        break
                    }
                    return appendBridgeCall(
                        "__kk_list_windowed_transform",
                        runtimeArguments,
                        canThrow: true
                    )
                case "zip" where !hasHOFLambdaArg && normalizedArgIDs.count == 1:
                    return appendBridgeCall("__kk_list_zip", [loweredReceiverID, normalizedArgIDs[0]])
                case "zip" where hasHOFLambdaArg && normalizedArgIDs.count == 2:
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return appendBridgeCall(
                        "__kk_list_zip_transform",
                        [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr],
                        canThrow: true
                    )
                case "zipWithNext" where normalizedArgIDs.isEmpty:
                    return appendBridgeCall("__kk_list_zipWithNext", [loweredReceiverID])
                case "zipWithNext" where hasHOFLambdaArg && normalizedArgIDs.count == 1:
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[0],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return appendBridgeCall(
                        "__kk_list_zipWithNextTransform",
                        [loweredReceiverID, fnPtrExpr, envPtrExpr],
                        canThrow: true
                    )
                default:
                    break
                }
            }
        }

        // Sequence windowed: 1-3 args (size, step=1, partialWindows=false) — STDLIB-276
        // Lambda-bearing `windowed` calls use the synthetic iterable HOF overload
        // and must not be rewritten to the sequence ABI here.
        if !hasHOFLambdaArg,
           (1...3).contains(args.count),
           calleeName == interner.intern("windowed")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || sema.bindings.isCollectionExpr(receiverExpr) && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                let sizeArg = normalizedArgIDs[0]
                let stepArg: KIRExprID
                if args.count >= 2 {
                    stepArg = normalizedArgIDs[1]
                } else {
                    stepArg = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                    instructions.append(.constValue(result: stepArg, value: .intLiteral(1)))
                }
                let partialArg: KIRExprID
                if args.count >= 3 {
                    partialArg = normalizedArgIDs[2]
                } else {
                    partialArg = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: partialArg, value: .intLiteral(0)))
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_windowed"),
                    arguments: [loweredReceiverID, sizeArg, stepArg, partialArg],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_array_toList"
                case "toMutableList":
                    "kk_array_toMutableList"
                case "toTypedArray":
                    "kk_array_copyOf"
                case "copyOf":
                    "kk_array_copyOf"
                case "concatToString":
                    "kk_chararray_concatToString"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            // String Iterable<Char> — route toList/iterator to specialised runtime (STDLIB-317)
            if isStringIterableType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    "kk_string_iterable_toList"
                case "iterator":
                    "kk_string_iterable_iterator"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForTerminalFallback = isSequenceLikeType(
                nonNullReceiverType,
                sema: sema,
                interner: interner
            )
            let useIterableRuntimeForTerminalFallback = (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForTerminalFallback || useIterableRuntimeForTerminalFallback {
                let toListID = interner.intern("toList")
                let constrainOnceID = interner.intern("constrainOnce")
                let distinctID = interner.intern("distinct")
                let sortedID = interner.intern("sorted")
                let sortedDescendingID = interner.intern("sortedDescending")
                let filterNotNullID = interner.intern("filterNotNull")
                let requireNoNullsID = interner.intern("requireNoNulls")
                let asIterableID = interner.intern("asIterable")
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
                let iterableLastCallee = interner.intern("kk_iterable_last")
                let seqLastOrNullCallee = interner.intern("kk_sequence_lastOrNull")
                let seqSingleCallee = interner.intern("kk_sequence_single")
                let seqSingleOrNullCallee = interner.intern("kk_sequence_singleOrNull")
                let seqCountCallee = interner.intern("kk_sequence_count")
                let seqAnyCallee = interner.intern("kk_sequence_any")
                let iterableAnyCallee = interner.intern("kk_iterable_any")
                let seqNoneCallee = interner.intern("kk_sequence_none")
                let seqToListCallee = interner.intern("kk_sequence_to_list")

                let runtimeCallee: InternedString? = switch calleeName {
                case toListID:
                    seqToListCallee
                case constrainOnceID:
                    interner.intern("kk_sequence_constrainOnce")
                case distinctID:
                    interner.intern("kk_sequence_distinct")
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
                case interner.intern("asSequence"):
                    useIterableRuntimeForTerminalFallback
                        // swiftlint:disable:next void_function_in_ternary
                        ? interner.intern("kk_iterable_asSequence")
                        : interner.intern("kk_sequence_asSequence")
                case asIterableID:
                    interner.intern("kk_sequence_asIterable")
                case withIndexID:
                    interner.intern("kk_sequence_withIndex")
                case firstID:
                    seqFirstCallee
                case firstOrNullID:
                    seqFirstOrNullCallee
                case lastID:
                    useIterableRuntimeForTerminalFallback ? iterableLastCallee : seqLastCallee
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
                        chosenCallee: sema.bindings.callBindings[exprID]?.chosenCallee,
                        useIterableFallback: useIterableRuntimeForTerminalFallback,
                        sema: sema,
                        interner: interner
                    )
                case toMutableSetID:
                    interner.intern(useIterableRuntimeForTerminalFallback
                        ? "kk_iterable_toMutableSet"
                        : "kk_sequence_toMutableSet")
                case toSortedSetID:
                    interner.intern("kk_sequence_toSortedSet")
                case toHashSetID:
                    interner.intern("kk_sequence_toHashSet")
                case unzipID:
                    interner.intern("kk_sequence_unzip")
                case anyID:
                    useIterableRuntimeForTerminalFallback ? iterableAnyCallee : seqAnyCallee
                case noneID:
                    seqNoneCallee
                default:
                    nil
                }
                if let runtimeCallee {
                    // any()/none() with no predicate: pass fnPtr=0, closure=0 sentinel
                    if runtimeCallee == seqAnyCallee || runtimeCallee == iterableAnyCallee || runtimeCallee == seqNoneCallee {
                        let zeroExpr = arena.appendExpr(.intLiteral(0), type: nil)
                        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        instructions.append(.call(
                            symbol: nil,
                            callee: runtimeCallee,
                            arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        return result
                    }
                    let canThrow = runtimeCallee == seqFirstCallee
                        || runtimeCallee == seqFirstOrNullCallee
                        || runtimeCallee == seqLastCallee
                        || runtimeCallee == iterableLastCallee
                        || runtimeCallee == seqLastOrNullCallee
                        || runtimeCallee == seqCountCallee
                        || runtimeCallee == seqToListCallee
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner),
               interner.resolve(calleeName) == "pattern"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_regex_pattern"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        return nil
    }
}
