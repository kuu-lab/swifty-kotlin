// swiftlint:disable file_length
import RuntimeABI

/// Member-call fallback resolution for Collection-typed receivers
/// (List / Iterable / Set / Sequence / Collection): supported-member
/// check, parameter-mapping, result-type inference, lambda-expectation
/// inference, and the receiver-kind predicates.
///
/// Split out from `CallTypeChecker+MemberCallFallbacks.swift`.
extension CallTypeChecker {
    private func stdlibSurfaceResultType(
        for spec: StdlibSurfaceSpec,
        memberName: InternedString,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        switch spec.returnStrategy {
        case .any, .nullableAny:
            return nil
        case .receiver:
            guard isMapReceiver else { return nil }
            let mapEntryTypes = stdlibSurfaceMapEntryTypes(receiverElementType: receiverElementType, sema: sema)
            return makeSyntheticMapType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                keyType: mapEntryTypes.key,
                valueType: mapEntryTypes.value
            )
        case .receiverElement:
            return receiverElementType
        case .nullableReceiverElement:
            return sema.types.makeNullable(receiverElementType)
        case .destinationArgument:
            guard let firstArg = args.first else { return nil }
            return sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
        case .unit:
            return sema.types.unitType
        case .boolean:
            return sema.types.booleanType
        case .int:
            return sema.types.intType
        case .double:
            return sema.types.doubleType
        case .list:
            if memberName == knownNames.flatMapIndexed {
                return nil
            }
            let elementType = memberName == knownNames.filterNotNull
                ? sema.types.makeNonNullable(receiverElementType)
                : receiverElementType
            return makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: elementType
            )
        case .set:
            return makeSyntheticSetType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        case .map:
            return makeSyntheticMapType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                keyType: sema.types.anyType,
                valueType: sema.types.anyType
            )
        case .sequence:
            if memberName == knownNames.flatMapIndexed {
                return nil
            }
            let elementType = memberName == knownNames.filterNotNull
                ? sema.types.makeNonNullable(receiverElementType)
                : receiverElementType
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: elementType
            )
        }
    }

    func collectionFallbackResultType(
        memberName: InternedString,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        isListReceiver: Bool,
        isSetReceiver: Bool,
        isSequenceReceiver: Bool = false,
        isMutableReceiver: Bool = false,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        sema: SemaModule,
        expectedType: TypeID? = nil,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let surfaceOwnerKinds = stdlibSurfaceOwnerKindsForCollectionFallback(
            isIterableReceiver: true,
            isListReceiver: isListReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver
        )
        // chunked(size): returns Sequence<List<T>> for sequence receivers,
        // List<List<T>> for list/collection receivers.
        if memberName == knownNames.chunked, args.count == 1 {
            let chunkType = makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: chunkType
                )
            }
            if let listSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsListFQName) {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(chunkType)],
                    nullability: .nonNull
                )))
            }
        }
        // filterNotNull() on a List<T?> is bound directly to the bundled
        // Kotlin-source declaration (see didBindListFilterNotNullSource
        // above), so it has no stdlibSurfaceSpecForCollectionFallback entry.
        // Compute its List<T> result type explicitly instead of falling
        // through to the generic `Any` default below.
        if memberName == knownNames.filterNotNull, isListReceiver, args.isEmpty {
            return makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.makeNonNullable(receiverElementType)
            )
        }
        if let surfaceSpec = stdlibSurfaceSpecForCollectionFallback(
            memberName: memberName,
            argCount: args.count,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ),
           let resultType = stdlibSurfaceResultType(
            for: surfaceSpec,
            memberName: memberName,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            args: args,
            sema: sema,
            interner: interner
           ) {
            return resultType
        }
        if memberName == knownNames.filter {
            return makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        let intReturningMembers = knownNames.intReturningMembers
        if intReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.int, .nonNull))
        }

        // sum()/maxBy() use the receiver element type as the result.
        if memberName == knownNames.sum || memberName == knownNames.maxBy {
            return receiverElementType
        }

        if memberName == knownNames.average {
            return sema.types.doubleType
        }

        let transformExpr: ExprID? = if memberName == knownNames.chunked, args.count == 2 {
            args[1].expr
        } else if memberName == knownNames.windowed, (2...4).contains(args.count),
                  let lastExpr = args.last?.expr,
                  let lastExprNode = ctx.ast.arena.expr(lastExpr),
                  lastExprNode.isLambdaOrCallableRef
        {
            // Defaulted windowed parameters may be omitted before the trailing
            // transform, so the transform is always the final supplied argument.
            lastExpr
        } else {
            nil
        }
        if let transformExpr {
            let lambdaReturnType = collectionFallbackTransformResultType(
                transformExpr: transformExpr,
                ctx: ctx,
                sema: sema
            )

            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: lambdaReturnType
                )
            }

            if let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(lambdaReturnType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        }

        if memberName == knownNames.windowed {
            let lastArgIsFunctionLike: Bool = if let lastExpr = args.last?.expr,
                                                 let lastExprNode = ctx.ast.arena.expr(lastExpr) {
                lastExprNode.isLambdaOrCallableRef
            } else {
                false
            }
            if !lastArgIsFunctionLike,
               let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first
            {
                let windowType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
                if isSequenceReceiver {
                    return makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: windowType
                    )
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(windowType)],
                    nullability: .nonNull
                )))
            }
        }

        if memberName == knownNames.requireNoNulls {
            let elementType = sema.types.makeNonNullable(receiverElementType)
            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: elementType
                )
            }
            if let iterableSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsIterableFQName) {
                return sema.types.make(.classType(ClassType(
                    classSymbol: iterableSymbol,
                    args: [.out(elementType)],
                    nullability: .nonNull
                )))
            }
        }

        let boolReturningMembers = knownNames.boolReturningMembers
        if boolReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.boolean, .nonNull))
        }

        if memberName == knownNames.sort ||
            memberName == knownNames.sortBy ||
            memberName == knownNames.sortByDescending ||
            memberName == knownNames.clear
        {
            return sema.types.unitType
        }

        if memberName == knownNames.joinToString {
            return sema.types.stringType
        }

        if memberName == knownNames.putAll {
            return sema.types.unitType
        }

        let destinationCollectionReturningMembers = knownNames.destinationCollectionReturningMembers
        if destinationCollectionReturningMembers.contains(memberName),
           let firstArg = args.first
        {
            return sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
        }

        if memberName == knownNames.flatMapIndexed {
            let lambdaReturnType: TypeID = if let firstArg = args.first,
                                              case let .functionType(fnType) = sema.types.kind(
                                                  of: sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
                                              ) {
                fnType.returnType
            } else {
                sema.types.anyType
            }
            let flattenedElementType: TypeID = if case let .classType(classType) = sema.types.kind(
                of: sema.types.makeNonNullable(lambdaReturnType)
            ), let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .out(type), let .in(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: flattenedElementType
                )
            }
            if let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(flattenedElementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        }

        if memberName == knownNames.find {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == knownNames.firstNotNullOf {
            if let expectedType {
                return sema.types.makeNonNullable(expectedType)
            }
            guard let firstArg = args.first else { return sema.types.anyType }
            if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType) {
                return sema.types.makeNonNullable(fnType.returnType)
            }
            return sema.types.anyType
        }

        if memberName == knownNames.firstNotNullOfOrNull {
            if let expectedType {
                return sema.types.makeNullable(sema.types.makeNonNullable(expectedType))
            }
            guard let firstArg = args.first else { return sema.types.nullableAnyType }
            if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType) {
                return sema.types.makeNullable(sema.types.makeNonNullable(fnType.returnType))
            }
            return sema.types.nullableAnyType
        }

        if memberName == knownNames.asIterable {
            return makeSyntheticIterableType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }

        if memberName == knownNames.elementAt
            || memberName == knownNames.single
        {
            return receiverElementType
        }

        if memberName == knownNames.getOrNull
            || memberName == knownNames.elementAtOrNull
            || memberName == knownNames.firstOrNull
            || memberName == knownNames.lastOrNull
            || memberName == knownNames.singleOrNull
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == knownNames.getOrElse, !isMapReceiver {
            return receiverElementType
        }

        if memberName == knownNames.elementAtOrElse {
            return receiverElementType
        }

        if memberName == knownNames.plus || memberName == knownNames.minus {
            // plus/minus return the same Map type as the receiver.
            // receiverElementType for maps is Map.Entry<K,V>, so reconstruct Map<K,V>.
            if case let .classType(entryType) = sema.types.kind(of: receiverElementType),
               entryType.args.count >= 2
            {
                let keyArg = entryType.args[0]
                let valueArg = entryType.args[1]
                if let mapSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsMapFQName) {
                    // Map.Entry<out K, out V> declares K covariantly, but the enclosing
                    // Map<K, V> declares K invariant. Reusing keyArg's `.out` projection
                    // as-is here would make this reconstructed type a strict supertype of
                    // Map<K, V>, which callers expecting the exact type (e.g. a data class
                    // copy() parameter) would then reject. Project K back to `.invariant`.
                    let keyType: TypeID = switch keyArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [.invariant(keyType), valueArg],
                        nullability: .nonNull
                    )))
                }
            }
            return sema.types.anyType
        }

        if memberName == knownNames.getValue
            || memberName == knownNames.getOrDefault
            || memberName == knownNames.getOrPut
            || (memberName == knownNames.getOrElse && isMapReceiver)
        {
            if case let .classType(classType) = sema.types.kind(of: receiverElementType),
               classType.args.count >= 2
            {
                return switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            }
            return sema.types.anyType
        }

        if memberName == knownNames.minBy || memberName == knownNames.min {
            return receiverElementType
        }

        if memberName == knownNames.maxOrNull
            || memberName == knownNames.minOrNull
            || memberName == knownNames.maxByOrNull
            || memberName == knownNames.minByOrNull
            || memberName == knownNames.firstOrNull
            || memberName == knownNames.lastOrNull
            || memberName == knownNames.singleOrNull
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == knownNames.maxOfOrNull
            || memberName == knownNames.minOfOrNull
        {
            return sema.types.nullableAnyType
        }

        // Map.toList() pairs up each entry instead of yielding Map.Entry values.
        if memberName == knownNames.toList, isMapReceiver,
           let pairSymbol = sema.symbols.lookupByShortName(knownNames.pair).first
        {
            let entryTypes = stdlibSurfaceMapEntryTypes(receiverElementType: receiverElementType, sema: sema)
            let pairType = sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.invariant(entryTypes.key), .invariant(entryTypes.value)],
                nullability: .nonNull
            )))
            return makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: pairType
            )
        }

        // MutableList<E>.subList(...): MutableList<E> overrides List<E>.subList(...): List<E>.
        if memberName == knownNames.subList,
           let subListOwnerSymbol = sema.symbols.lookupByShortName(
               isMutableReceiver ? knownNames.mutableList : knownNames.list
           ).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: subListOwnerSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }
        if memberName == knownNames.toList
            || memberName == knownNames.slice
            || memberName == knownNames.minusElement,
           let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first
        {
            if memberName == knownNames.minusElement, isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: receiverElementType
                )
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toTypedArray {
            return makeSyntheticArrayType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }

        if memberName == knownNames.toIntArray,
           let intArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinIntArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: intArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toCharArray,
           let charArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinCharArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: charArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toBooleanArray,
           let booleanArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinBooleanArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: booleanArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toShortArray,
           let shortArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinShortArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: shortArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toDoubleArray,
           let doubleArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinDoubleArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: doubleArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toFloatArray,
           let floatArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinFloatArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: floatArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toLongArray,
           let longArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinLongArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: longArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toByteArray,
           let byteArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinByteArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: byteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toUByteArray,
           let ubyteArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinUByteArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ubyteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toUShortArray,
           let ushortArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinUShortArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ushortArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toUIntArray,
           let uintArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinUIntArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: uintArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toULongArray,
           let ulongArraySymbol = sema.symbols.lookup(fqName: knownNames.kotlinULongArrayFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ulongArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.toMutableList,
           let mutableListSymbol = sema.symbols.lookupByShortName(knownNames.mutableList).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableListSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.reduceOrNull
            || memberName == knownNames.reduceIndexedOrNull
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == knownNames.runningReduce
            || memberName == knownNames.runningReduceIndexed,
           let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.scan
            || memberName == knownNames.scanIndexed
            || memberName == knownNames.runningFold
            || memberName == knownNames.runningFoldIndexed,
           let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first
        {
            // scan/runningFold variants return List<R> where R is the accumulator type,
            // derived from the initial value (first argument).
            let accumulatorType: TypeID
            if args.count >= 1, let inferredInitType = sema.bindings.exprTypes[args[0].expr] {
                accumulatorType = inferredInitType
            } else {
                accumulatorType = sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(accumulatorType)],
                nullability: .nonNull
            )))
        }

        if isListReceiver || isSetReceiver,
           isSetReturningCollectionBinaryMember(memberName, interner: interner),
           let setSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsSetFQName)
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == knownNames.withIndex,
           let iterableSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsIterableFQName),
           let indexedValueSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsIndexedValueFQName)
        {
            let indexedValueType = sema.types.make(.classType(ClassType(
                classSymbol: indexedValueSymbol,
                args: [.out(receiverElementType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: iterableSymbol,
                args: [.out(indexedValueType)],
                nullability: .nonNull
            )))
        }

        // sorted(), sortedDescending(), sortedWith(), sorted(comparator): return List<E>
        // reversed(), asReversed(), distinct(), distinctBy(): return List<E>
        let listPreservingMembers = knownNames.listPreservingMembers
        if memberName == knownNames.shuffled, isSequenceReceiver {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        if memberName == knownNames.sorted || memberName == knownNames.sortedDescending,
           isSequenceReceiver
        {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        if listPreservingMembers.contains(memberName),
           let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        // flatten(): for List<List<E>>, returns List<E> (element type of the outer list elements).
        // Skip this for sequence receivers — the existing sequence HOF logic handles them,
        // and mixed-type sequence flatten should fail gracefully (matching kotlinc).
        if memberName == knownNames.flatten,
           !isSequenceReceiver,
           let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first
        {
            // The receiverElementType is List<E> (the inner list). Extract E from it.
            let innerElementType: TypeID
            if case let .classType(innerListType) = sema.types.kind(of: receiverElementType),
               let firstArg = innerListType.args.first
            {
                innerElementType = switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                innerElementType = sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(innerElementType)],
                nullability: .nonNull
            )))
        }

        // zip(other): returns List<Pair<A,B>> or Sequence<Pair<A,B>> where A
        // is receiver element type and B is the other collection element type.
        if memberName == knownNames.zip,
           !args.isEmpty,
           let pairSymbol = sema.symbols.lookupByShortName(knownNames.pair).first
        {
            let otherElementType: TypeID
            if let otherListType = sema.bindings.exprTypes[args[0].expr] {
                let nonNullOther = sema.types.makeNonNullable(otherListType)
                if case let .classType(classType) = sema.types.kind(of: nonNullOther),
                   let firstArg = classType.args.first
                {
                    otherElementType = switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    otherElementType = sema.types.anyType
                }
            } else {
                otherElementType = sema.types.anyType
            }
            if args.count >= 2 {
                let transformType = sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
                let transformedElementType: TypeID
                if case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType)) {
                    transformedElementType = fnType.returnType
                } else {
                    transformedElementType = sema.types.anyType
                }
                if isSequenceReceiver {
                    return makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: transformedElementType
                    )
                }
                return makeSyntheticListType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: transformedElementType
                )
            }
            let pairType = sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.invariant(receiverElementType), .invariant(otherElementType)],
                nullability: .nonNull
            )))
            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: pairType
                )
            }
            return makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: pairType
            )
        }

        // unzip(): for List<Pair<A,B>>, returns Pair<List<A>, List<B>>
        if memberName == knownNames.unzip,
           let listSymbol = sema.symbols.lookupByShortName(knownNames.list).first,
           let pairSymbol = sema.symbols.lookupByShortName(knownNames.pair).first
        {
            // receiverElementType should be Pair<A, B>; extract A and B
            let aType: TypeID
            let bType: TypeID
            if case let .classType(pairClassType) = sema.types.kind(of: receiverElementType),
               pairClassType.args.count >= 2
            {
                aType = switch pairClassType.args[0] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
                bType = switch pairClassType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                aType = sema.types.anyType
                bType = sema.types.anyType
            }
            let listAType = sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(aType)],
                nullability: .nonNull
            )))
            let listBType = sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(bType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(listAType), .out(listBType)],
                nullability: .nonNull
            )))
        }

        // iterator(): returns MutableIterator<E> for Mutable{Collection,List,Set}
        // receivers (real Kotlin's covariant MutableIterable override), Iterator<E>
        // otherwise.
        if memberName == knownNames.iterator {
            if isMutableReceiver,
               let mutableIteratorSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsMutableIteratorFQName)
            {
                return sema.types.make(.classType(ClassType(
                    classSymbol: mutableIteratorSymbol,
                    args: [.out(receiverElementType)],
                    nullability: .nonNull
                )))
            }
            if let iteratorSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsIteratorFQName) {
                return sema.types.make(.classType(ClassType(
                    classSymbol: iteratorSymbol,
                    args: [.out(receiverElementType)],
                    nullability: .nonNull
                )))
            }
        }

        if isSequenceReceiver,
           memberName == knownNames.windowed,
           args.count == 4
        {
            let transformExpr = args[3].expr
            let transformType = sema.bindings.exprTypes[transformExpr] ?? sema.types.anyType
            let transformedElementType: TypeID
            if case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType)) {
                transformedElementType = fnType.returnType
            } else {
                transformedElementType = sema.types.anyType
            }
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: transformedElementType
            )
        }

        if isSequenceReceiver,
           memberName == knownNames.chunked,
           args.count == 2
        {
            let transformExpr = args[1].expr
            let transformType = sema.bindings.exprTypes[transformExpr] ?? sema.types.anyType
            let transformedElementType: TypeID
            if case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType)) {
                transformedElementType = fnType.returnType
            } else {
                transformedElementType = sema.types.anyType
            }
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: transformedElementType
            )
        }

        if memberName == knownNames.asSequence {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }

        return sema.types.anyType
    }

    private func collectionFallbackTransformResultType(
        transformExpr: ExprID,
        ctx: TypeInferenceContext,
        sema: SemaModule
    ) -> TypeID {
        // Prefer the lambda body's inferred type over the stored function type,
        // because inferLambdaLiteralExpr binds the lambda to the *expected* type
        // (e.g. (List<T>) -> Any) rather than the *inferred* return type.
        if let lambdaNode = ctx.ast.arena.expr(transformExpr),
           case let .lambdaLiteral(_, body: bodyExprID, _, _) = lambdaNode,
           let bodyType = sema.bindings.exprTypes[bodyExprID],
           bodyType != sema.types.nothingType
        {
            return bodyType
        }
        if let transformType = sema.bindings.exprTypes[transformExpr],
           case let .functionType(fnType) = sema.types.kind(of: transformType),
           fnType.returnType != sema.types.anyType
        {
            return fnType.returnType
        }
        return sema.types.anyType
    }

    private func stdlibSurfaceDestinationTypes(
        args: [CallArgument],
        sema: SemaModule
    ) -> (collectionElement: TypeID, mapKey: TypeID, mapValue: TypeID) {
        let destinationType = args.first.flatMap { sema.bindings.exprTypes[$0.expr] } ?? sema.types.anyType
        let destinationCollectionElementType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                               destClassType.args.count >= 1
        {
            switch destClassType.args[0] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        let destinationMapKeyType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                      destClassType.args.count >= 2
        {
            switch destClassType.args[0] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        let destinationMapValueType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                        destClassType.args.count >= 2
        {
            switch destClassType.args[1] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        return (destinationCollectionElementType, destinationMapKeyType, destinationMapValueType)
    }

    private func stdlibSurfaceMapEntryTypes(
        receiverElementType: TypeID,
        sema: SemaModule
    ) -> (key: TypeID, value: TypeID) {
        guard case let .classType(entryType) = sema.types.kind(of: receiverElementType),
              entryType.args.count >= 2
        else {
            return (sema.types.anyType, sema.types.anyType)
        }
        let keyType: TypeID = switch entryType.args[0] {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
        let valueType: TypeID = switch entryType.args[1] {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
        return (keyType, valueType)
    }

    private func stdlibSurfaceLambdaReturnType(
        _ strategy: StdlibSurfaceLambdaReturnStrategy,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let destinationTypes = stdlibSurfaceDestinationTypes(args: args, sema: sema)
        switch strategy {
        case .any:
            return sema.types.anyType
        case .nullableAny:
            return sema.types.nullableAnyType
        case .boolean:
            return sema.types.booleanType
        case .int:
            return sema.types.intType
        case .double:
            return sema.types.doubleType
        case .unit:
            return sema.types.unitType
        case .destinationElement:
            return destinationTypes.collectionElement
        case .destinationMapKey:
            return destinationTypes.mapKey
        case .destinationMapValue:
            return destinationTypes.mapValue
        case .collectionOfDestinationElement:
            if let collectionSymbol = sema.symbols.lookupByShortName(knownNames.collection).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: collectionSymbol,
                    args: [.out(destinationTypes.collectionElement)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        case .pairOfDestinationKeyValue:
            if let pairSymbol = sema.symbols.lookupByShortName(knownNames.pair).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(destinationTypes.mapKey), .out(destinationTypes.mapValue)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        }
    }

    private func stdlibSurfaceLambdaExpectation(
        for spec: StdlibSurfaceSpec,
        receiverElementType: TypeID,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let argumentIndex: Int
        let parameterTypes: [TypeID]
        let returnStrategy: StdlibSurfaceLambdaReturnStrategy
        switch spec.lambdaExpectation {
        case .none:
            return nil
        case let .receiverElement(argumentIndex: index, returnStrategy: strategy),
             let .destinationElement(argumentIndex: index, returnStrategy: strategy):
            argumentIndex = index
            parameterTypes = [receiverElementType]
            returnStrategy = strategy
        case let .indexedReceiverElement(argumentIndex: index, returnStrategy: strategy),
             let .indexedDestinationElement(argumentIndex: index, returnStrategy: strategy):
            argumentIndex = index
            parameterTypes = [sema.types.intType, receiverElementType]
            returnStrategy = strategy
        case let .mapKey(argumentIndex: index, returnStrategy: strategy):
            let mapEntryTypes = stdlibSurfaceMapEntryTypes(receiverElementType: receiverElementType, sema: sema)
            argumentIndex = index
            parameterTypes = [mapEntryTypes.key]
            returnStrategy = strategy
        case let .mapValue(argumentIndex: index, returnStrategy: strategy):
            let mapEntryTypes = stdlibSurfaceMapEntryTypes(receiverElementType: receiverElementType, sema: sema)
            argumentIndex = index
            parameterTypes = [mapEntryTypes.value]
            returnStrategy = strategy
        }
        let returnType = stdlibSurfaceLambdaReturnType(
            returnStrategy,
            args: args,
            sema: sema,
            interner: interner
        )
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: returnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: argumentIndex, expectedType: expectedType)
    }

    func collectionFallbackLambdaExpectation(
        memberName: InternedString,
        argCount: Int,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isMutableMapReceiver: Bool,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        interner: StringInterner,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let knownNames = KnownCompilerNames(interner: interner)
        let surfaceOwnerKinds: [StdlibSurfaceOwnerKind] = if isMapReceiver {
            [.map]
        } else if isSetReceiver {
            [.set]
        } else {
            [.list, .sequence]
        }
        if let surfaceSpec = stdlibSurfaceSpecForCollectionFallback(
            memberName: memberName,
            argCount: argCount,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ),
           let surfaceExpectation = stdlibSurfaceLambdaExpectation(
            for: surfaceSpec,
            receiverElementType: receiverElementType,
            args: args,
            sema: sema,
            interner: interner
           ) {
            return surfaceExpectation
        }

        // Map.firstNotNullOf and Map.firstNotNullOfOrNull are source-backed
        // members, so they intentionally have no runtime surface entry. Keep
        // their transform contextualized as Map.Entry<K, V> while the fallback
        // binds the source declaration.
        if isMapReceiver,
           argCount == 1,
           memberName == knownNames.firstNotNullOf
               || memberName == knownNames.firstNotNullOfOrNull
        {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: sema.types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        let boolOneParamMembers = knownNames.boolOneParamMembers
        let oneParamMembers = knownNames.oneParamMembers
        if memberName == knownNames.getOrDefault {
            guard isMapReceiver else {
                return nil
            }
        }
        if oneParamMembers.contains(memberName), argCount == 1 {
            let lambdaReturnType = boolOneParamMembers.contains(memberName)
                ? sema.types.make(.primitive(.boolean, .nonNull))
                : memberName == knownNames.sumOf || memberName == knownNames.sumBy
                ? sema.types.intType
                : memberName == knownNames.sumByDouble
                ? sema.types.doubleType
                : memberName == knownNames.firstNotNullOf || memberName == knownNames.firstNotNullOfOrNull
                ? sema.types.nullableAnyType
                : memberName == knownNames.sortedBy || memberName == knownNames.sortedByDescending
                ? sema.types.nullableAnyType
                : memberName == knownNames.sortBy || memberName == knownNames.sortByDescending
                ? sema.types.nullableAnyType
                : sema.types.anyType
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: lambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.maxWith
            || memberName == knownNames.maxWithOrNull
            || memberName == knownNames.minWith
            || memberName == knownNames.minWithOrNull,
           argCount == 1,
           let comparatorSymbol = sema.symbols.lookup(fqName: knownNames.kotlinComparatorFQName)
        {
            let expectedType = sema.types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.in(receiverElementType)],
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.maxOfWith
            || memberName == knownNames.maxOfWithOrNull
            || memberName == knownNames.minOfWith
            || memberName == knownNames.minOfWithOrNull,
           argCount == 2
        {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: sema.types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // zip(other, transform): transform receives the receiver element and
        // the other collection element.
        if memberName == knownNames.zip, argCount == 2 {
            let otherElementType: TypeID
            if let otherCollectionType = sema.bindings.exprTypes[args[0].expr] {
                let nonNullOther = sema.types.makeNonNullable(otherCollectionType)
                if case let .classType(classType) = sema.types.kind(of: nonNullOther),
                   let firstArg = classType.args.first
                {
                    otherElementType = switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    otherElementType = sema.types.anyType
                }
            } else {
                otherElementType = sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType, otherElementType],
                returnType: sema.types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // chunked(size, transform): transform receives List<T> and returns R
        if memberName == knownNames.chunked, argCount == 2 {
            // Build List<T> for the lambda parameter type; the transform receives
            // a List<T> chunk.
            let listType: TypeID
            if let listSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsListFQName) {
                listType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
            } else {
                listType = sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [listType],
                returnType: sema.types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // windowed(size, step, partialWindows, transform): transform receives List<T> and returns R
        if memberName == knownNames.windowed, (2...4).contains(argCount) {
            let lastArgIsFunctionLike: Bool = if let lastExpr = args.last?.expr,
                                                 let lastExprNode = ctx.ast.arena.expr(lastExpr) {
                lastExprNode.isLambdaOrCallableRef
            } else {
                false
            }
            if lastArgIsFunctionLike {
                let listType: TypeID
                if let listSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsListFQName) {
                    listType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(receiverElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    listType = sema.types.anyType
                }
                let expectedType = sema.types.make(.functionType(FunctionType(
                    params: [listType],
                    returnType: sema.types.nullableAnyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return (argumentIndex: argCount - 1, expectedType: expectedType)
            }
        }

        // joinToString(separator?, prefix?, postfix?, transform): transform receives the
        // element and returns a CharSequence (modeled loosely as Any, like chunked/windowed
        // above); it is always the trailing argument when the call site supplies one.
        if memberName == knownNames.joinToString, (1...4).contains(argCount) {
            let lastArgIsFunctionLike: Bool = if let lastExpr = args.last?.expr,
                                                 let lastExprNode = ctx.ast.arena.expr(lastExpr) {
                lastExprNode.isLambdaOrCallableRef
            } else {
                false
            }
            if lastArgIsFunctionLike {
                let expectedType = sema.types.make(.functionType(FunctionType(
                    params: [receiverElementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return (argumentIndex: argCount - 1, expectedType: expectedType)
            }
        }

        if memberName == knownNames.fold, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.foldIndexed, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.foldRight, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.foldRightIndexed, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.reduceRight, argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.reduce || memberName == knownNames.reduceOrNull, argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.reduceIndexed, argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.scan
            || memberName == knownNames.scanIndexed
            || memberName == knownNames.runningFold
            || memberName == knownNames.runningFoldIndexed, argCount == 2
        {
            // scan/runningFold variants: (acc: R, element: T) -> R
            // The accumulator type is unknown in the fallback path, so use Any;
            // indexed variants prepend the Int index parameter.
            let params: [TypeID] = if memberName == knownNames.scanIndexed
                || memberName == knownNames.runningFoldIndexed
            {
                [sema.types.intType, sema.types.anyType, receiverElementType]
            } else {
                [sema.types.anyType, receiverElementType]
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: params,
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.runningReduce
            || memberName == knownNames.runningReduceIndexed
            || memberName == knownNames.reduceRightIndexed
            || memberName == knownNames.reduceRightIndexedOrNull
            || memberName == knownNames.reduceRightOrNull
            || memberName == knownNames.reduceIndexedOrNull, argCount == 1
        {
            // reduce/runningReduce variants use receiver element type.
            let params: [TypeID] = if memberName == knownNames.runningReduceIndexed
                || memberName == knownNames.reduceIndexedOrNull
                || memberName == knownNames.reduceRightIndexed
                || memberName == knownNames.reduceRightIndexedOrNull
            {
                [sema.types.intType, receiverElementType, receiverElementType]
            } else {
                [receiverElementType, receiverElementType]
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: params,
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.sortedWith, argCount == 1 {
            let comparatorFQName: [InternedString] = knownNames.kotlinComparatorFQName
            let expectedType: TypeID = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.in(receiverElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.getOrPut, isMutableMapReceiver, argCount == 2 {
            let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: receiverElementType),
                                       classType.args.count >= 2
            {
                switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: valueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.getOrElse, isMapReceiver, argCount == 2 {
            let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: receiverElementType),
                                       classType.args.count >= 2
            {
                switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: valueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // List.getOrElse(index, { default }) — lambda takes Int (index), returns element type
        if memberName == knownNames.getOrElse, !isMapReceiver, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // List.elementAtOrElse(index, { default }) — same as getOrElse
        if memberName == knownNames.elementAtOrElse, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.binarySearchBy, (2...4).contains(argCount) {
            let keyType = args.indices.contains(0)
                ? (sema.bindings.exprTypes[args[0].expr] ?? sema.types.nullableAnyType)
                : sema.types.nullableAnyType
            let selectorReturnType: TypeID = if keyType == sema.types.errorType {
                sema.types.nullableAnyType
            } else {
                switch sema.types.kind(of: keyType) {
                case .nothing:
                    sema.types.nullableAnyType
                default:
                        sema.types.makeNonNullable(keyType)
                }
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: selectorReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: argCount - 1, expectedType: expectedType)
        }

        return nil
    }

    // MARK: - Array member fallback (STDLIB-087/088/089)
}
