import RuntimeABI

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

    /// KUU-4318: `containsAll`/`addAll`/`removeAll`/`retainAll` are bound by
    /// the synthetic collection fallback without consulting their real
    /// Collection-parameter signatures, and `add`/`remove`/`contains` bind the
    /// same way without an element-type check. A range expression keeps a
    /// scalar or nominal range type — `IntRange` is `Iterable` but not
    /// `Collection`, and `ClosedFloatingPointRange` is neither — so an
    /// unchecked argument reaches the runtime bridge and crashes with
    /// ClassCastException. Returns false when the single non-lambda argument
    /// cannot conform to any bundled overload shape so regular overload
    /// resolution reports the mismatch like kotlinc.
    func collectionFallbackBulkCallArgumentIsAdmissible(
        memberName: InternedString,
        args: [CallArgument],
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        let isContainsAll = memberName == knownNames.containsAll
        let isBulkMutation = memberName == knownNames.addAll
            || memberName == knownNames.removeAll
            || memberName == knownNames.retainAll
        // Map.remove takes a key and Map has no add/contains element members;
        // the entry element type must not be used as their parameter type.
        let isElementMember = !isMapReceiver
            && (memberName == knownNames.add
                || memberName == knownNames.remove
                || memberName == knownNames.contains)
        guard isContainsAll || isBulkMutation || isElementMember,
              args.count == 1,
              !args[0].isSpread
        else {
            return true
        }
        let argumentExpr = args[0].expr
        // Predicate overloads (`removeAll { }`, `retainAll { }`) take a
        // function, not a collection argument; leave them to the existing
        // lambda paths.
        if ctx.ast.arena.expr(argumentExpr)?.isLambdaOrCallableRef == true {
            return true
        }
        let sema = ctx.sema
        if sema.bindings.exprTypes[argumentExpr] == nil {
            var argumentCtx = ctx
            argumentCtx.callArgumentExprBeingInferred = argumentExpr
            _ = driver.inferExpr(argumentExpr, ctx: argumentCtx, locals: &locals)
        }
        let inferredArgumentType = sema.bindings.exprTypes[argumentExpr] ?? sema.types.anyType
        // KUU-569: restore the nominal range type for scalar-marked range
        // expressions so `IntRange`/`ClosedFloatingPointRange` conformance is
        // checked against the source-level type rather than the runtime handle.
        let argumentType = sourceLevelRangeArgumentType(
            argumentExpr,
            inferredType: inferredArgumentType,
            ctx: ctx
        )
        let nonNullArgumentType = sema.types.makeNonNullable(argumentType)
        guard nonNullArgumentType != sema.types.anyType,
              !typeContainsErrorType(nonNullArgumentType, sema: sema)
        else {
            return true
        }
        // add/remove/contains take the receiver's element type directly.
        if isElementMember {
            return sema.types.isSubtype(argumentType, receiverElementType)
        }
        // containsAll only has Collection-parameter overloads. The bulk
        // mutation members additionally accept Iterable/Array/Sequence
        // arguments through source extensions; those are normally bound by
        // bindMutableCollectionSourceExtension first, but admitting the shapes
        // here keeps receivers whose source candidates are unavailable on the
        // same synthetic path as before.
        var expectedShapeFQNames = [knownNames.kotlinCollectionsCollectionFQName]
        if isBulkMutation {
            expectedShapeFQNames.append(contentsOf: [
                knownNames.kotlinCollectionsIterableFQName,
                knownNames.kotlinArrayFQName,
                knownNames.kotlinSequenceFQName,
            ])
        }
        return expectedShapeFQNames.contains { fqName in
            guard let shapeSymbol = sema.symbols.lookup(fqName: fqName) else {
                return false
            }
            let expectedType = sema.types.make(.classType(ClassType(
                classSymbol: shapeSymbol,
                args: [.out(receiverElementType)],
                nullability: .nonNull
            )))
            return sema.types.isSubtype(argumentType, expectedType)
        }
    }

    /// KUU-4330: Map members admitted by the synthetic fallback
    /// (`contains`/`containsKey`/`containsValue`/`getValue`/`getOrDefault`/
    /// `getOrElse`/`getOrPut`/`putAll`/`plus`/`minus`) are not in
    /// `sourceBackedCollectionMemberNames`, so they bind here before regular
    /// overload resolution without consulting their real `K`/`V` parameter
    /// signatures — `map.containsValue(2..4)` compiled even though kotlinc
    /// rejects it. Validate each non-lambda argument against the key/value
    /// types carried by the receiver's `Map.Entry<K, V>` element type and
    /// return false when an argument provably cannot conform, so the call
    /// falls through to regular resolution which reports the mismatch.
    func collectionFallbackMapCallArgumentsAreAdmissible(
        memberName: InternedString,
        args: [CallArgument],
        receiverElementType: TypeID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> Bool {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        let resolvedName = interner.resolve(memberName)

        // Only members whose parameters are the map's key/value types (or
        // collections of keys/pairs derived from them) need checking. The
        // rest take no value arguments or only destination/lambda parameters
        // the fallback already models. `contains` never reaches this fallback
        // (tryCollectionMemberFallback rejects the name up front).
        guard [
            "containsKey", "containsValue", "getValue",
            "getOrDefault", "getOrElse", "getOrPut",
            "putAll", "plus", "minus",
        ].contains(resolvedName) else {
            return true
        }

        // K/V are recovered from the receiver's Map.Entry<K, V> element type.
        // Star projections or non-map element shapes leave nothing reliable
        // to check against, so they stay admissible like before.
        guard case let .classType(entryType) = sema.types.kind(
            of: sema.types.makeNonNullable(receiverElementType)
        ), entryType.args.count >= 2 else {
            return true
        }
        func projectedArgument(_ typeArg: TypeArg) -> TypeID {
            switch typeArg {
            case let .invariant(type), let .out(type), let .in(type): type
            case .star: sema.types.anyType
            }
        }
        let keyType = projectedArgument(entryType.args[0])
        let valueType = projectedArgument(entryType.args[1])

        func nominalArgumentType(
            _ fqName: [InternedString],
            arguments: [TypeArg]
        ) -> TypeID? {
            guard let symbol = sema.symbols.lookup(fqName: fqName) else {
                return nil
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: symbol,
                args: arguments,
                nullability: .nonNull
            )))
        }

        let mapArgumentType = nominalArgumentType(
            knownNames.kotlinCollectionsMapFQName,
            arguments: [.out(keyType), .out(valueType)]
        )
        let pairArgumentType: TypeID? = {
            guard let pairSymbol = sema.symbols.lookup(
                fqName: [interner.intern("kotlin"), knownNames.pair]
            ) ?? sema.symbols.lookupByShortName(knownNames.pair).first else {
                return nil
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(keyType), .out(valueType)],
                nullability: .nonNull
            )))
        }()
        let defaultValueFunctionType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))

        // `minus(key:)` / `minus(keys:)` and the `plus` overloads share one
        // call shape, so an unlabeled argument may conform to any of their
        // parameter types. Labeled arguments resolve to the matching
        // overload's parameter instead.
        var minusKeyCollectionShapes: [TypeID] = []
        for fqName in [
            knownNames.kotlinCollectionsIterableFQName,
            knownNames.kotlinArrayFQName,
            knownNames.kotlinSequenceFQName,
        ] {
            if let shape = nominalArgumentType(fqName, arguments: [.out(keyType)]) {
                minusKeyCollectionShapes.append(shape)
            }
        }
        var plusPairCollectionShapes: [TypeID] = []
        if let pairArgumentType {
            for fqName in [
                knownNames.kotlinCollectionsIterableFQName,
                knownNames.kotlinSequenceFQName,
                knownNames.kotlinArrayFQName,
            ] {
                if let shape = nominalArgumentType(fqName, arguments: [.out(pairArgumentType)]) {
                    plusPairCollectionShapes.append(shape)
                }
            }
        }
        var plusUnlabeledShapes: [TypeID] = []
        if let pairArgumentType { plusUnlabeledShapes.append(pairArgumentType) }
        if let mapArgumentType { plusUnlabeledShapes.append(mapArgumentType) }
        plusUnlabeledShapes.append(contentsOf: plusPairCollectionShapes)

        func expectationShapes(for argument: CallArgument, position: Int) -> [TypeID] {
            if let label = argument.label {
                switch interner.resolve(label) {
                case "key": return [keyType]
                case "value" where resolvedName == "containsValue": return [valueType]
                case "defaultValue":
                    switch resolvedName {
                    case "getOrDefault": return [valueType]
                    case "getOrElse", "getOrPut": return [defaultValueFunctionType]
                    default: return []
                    }
                case "from" where resolvedName == "putAll":
                    return mapArgumentType.map { [$0] } ?? []
                case "keys" where resolvedName == "minus": return minusKeyCollectionShapes
                case "pair" where resolvedName == "plus":
                    return pairArgumentType.map { [$0] } ?? []
                case "map" where resolvedName == "plus":
                    return mapArgumentType.map { [$0] } ?? []
                case "pairs" where resolvedName == "plus": return plusPairCollectionShapes
                default: return []
                }
            }
            switch (resolvedName, position) {
            case ("containsKey", 0), ("getValue", 0):
                return [keyType]
            case ("containsValue", 0):
                return [valueType]
            case ("getOrDefault", 0):
                return [keyType]
            case ("getOrDefault", 1):
                return [valueType]
            case ("getOrElse", 0), ("getOrPut", 0):
                return [keyType]
            case ("getOrElse", 1), ("getOrPut", 1):
                return [defaultValueFunctionType]
            case ("putAll", 0):
                return mapArgumentType.map { [$0] } ?? []
            case ("minus", 0):
                return [keyType] + minusKeyCollectionShapes
            case ("plus", 0):
                return plusUnlabeledShapes
            default:
                return []
            }
        }

        for (index, argument) in args.enumerated() {
            guard !argument.isSpread else { continue }
            // Lambda and callable-reference arguments are typed by the
            // fallback's lambda expectation paths, not by this check.
            if ctx.ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                continue
            }
            let shapes = expectationShapes(for: argument, position: index)
            guard !shapes.isEmpty else { continue }
            let argumentExpr = argument.expr
            // Infer without an expected type: a mismatched literal binds the
            // error type under a foreign expected type and would be skipped
            // below (`getOrDefault(1, 2)` on a `Map<Int, String>`), while
            // plain inference keeps the real argument type for the subtype
            // check. Unsuffixed integer literals adapt through
            // `integerLiteralFitsParameter` instead, like kotlinc's literal
            // typing against the substituted parameter type.
            let inferredArgumentType: TypeID
            if let boundType = sema.bindings.exprTypes[argumentExpr] {
                inferredArgumentType = boundType
            } else {
                var argumentCtx = ctx
                argumentCtx.callArgumentExprBeingInferred = argumentExpr
                inferredArgumentType = driver.inferExpr(
                    argumentExpr,
                    ctx: argumentCtx,
                    locals: &locals
                )
            }
            // KUU-569: restore the nominal range type for scalar-marked range
            // expressions so `IntRange`/`ClosedFloatingPointRange` conformance
            // is checked against the source-level type rather than the runtime
            // handle — `map.getValue(2..4)` must see `IntRange`, not Int.
            let argumentType = sourceLevelRangeArgumentType(
                argumentExpr,
                inferredType: inferredArgumentType,
                ctx: ctx
            )
            let nonNullArgumentType = sema.types.makeNonNullable(argumentType)
            guard nonNullArgumentType != sema.types.anyType,
                  !typeContainsErrorType(nonNullArgumentType, sema: sema)
            else {
                continue
            }
            var widenedLiteralType: TypeID?
            let conforms = shapes.contains { expectedType in
                if sema.types.isSubtype(argumentType, expectedType) {
                    return true
                }
                // Unsuffixed integer literals keep their Int inference; accept
                // them when they fit an integer primitive shape like kotlinc's
                // literal typing, and rebind the literal to that shape so
                // downstream lowering sees the parameter type (`1` for a `Long`
                // key).
                if integerLiteralFitsParameter(
                    argumentExpr,
                    parameterType: expectedType,
                    ctx: ctx
                ) {
                    widenedLiteralType = sema.types.makeNonNullable(expectedType)
                    return true
                }
                return false
            }
            if !conforms {
                return false
            }
            if let widenedLiteralType {
                sema.bindings.bindExprType(argumentExpr, type: widenedLiteralType)
            }
        }
        return true
    }
}
