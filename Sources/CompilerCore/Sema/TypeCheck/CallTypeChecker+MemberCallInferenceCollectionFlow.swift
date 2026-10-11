// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Collection/Flow higher-order-function names deferred for contextual
    /// lambda typing in `tryInferMemberCallCollectionFlowSpecials`.
    private static let collectionHOFNames: Set<String> = [
        "map", "filter", "filterNot", "mapNotNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
        "fold", "foldRight", "reduce", "reduceOrNull", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "foldIndexed", "foldRightIndexed", "reduceIndexed", "reduceIndexedOrNull",
        "scan", "scanIndexed", "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed",
        "groupBy", "sortedBy", "count", "first", "last", "single", "singleOrNull", "find", "findLast", "indexOf", "lastIndexOf", "contains", "containsAll", "firstOrNull", "lastOrNull",
        "associateBy", "associateWith", "associate", "associateTo", "associateByTo", "associateWithTo", "groupByTo",
        "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo", "mapIndexedTo", "flatMapIndexedTo",
        "mapIndexedNotNullTo", "filterIndexedTo", "filterNotNullTo",
        "mapKeysTo", "mapValuesTo",
        "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed",
        "onEach", "onEachIndexed", "withIndex", "filterNotNull", "requireNoNulls",
        "sumOf", "sumBy", "sumByDouble", "min", "maxOrNull", "minOrNull",
        "indexOfFirst", "indexOfLast", "binarySearch", "binarySearchBy",
        "maxBy", "minBy", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull",
        "maxOf", "minOf",
        "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
        "sorted", "sortedDescending", "sortedByDescending", "sortedWith", "sortedArrayWith", "partition", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "distinctBy", "zip", "zipWithNext",
        "max",
        "flatten", "asSequence", "sum", "average", "reversed", "asReversed", "intersect", "union", "subtract",
        "sort", "sortBy", "sortByDescending", "sortWith",
    ]

    private static let flowHOFNames: Set<String> = ["map", "filter", "collect"]
    private static let mapOnlyCollectionHOFNames: Set<String> = ["mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues"]

    /// Members the collection fast path may claim for a `Map` receiver.
    /// `Map<K, V>` is not an `Iterable` in Kotlin, so Iterable/Collection-only
    /// members (filterNotNull, fold, first, groupBy, ...) must not be claimed:
    /// they fall through to regular overload resolution which reports
    /// SEMA-0024, instead of binding a result type with no callee that lowers
    /// to an undefined symbol (LINK-0001). `forEach` and the destination
    /// overloads (`flatMapTo`) stay on regular resolution for lambda arity
    /// and Iterable/Sequence-return overload selection.
    private static let mapCollectionHOFNames: Set<String> = [
        "map", "mapNotNull", "mapKeys", "mapValues", "mapTo", "mapNotNullTo", "mapKeysTo", "mapValuesTo",
        "filter", "filterNot", "filterKeys", "filterValues", "filterTo", "filterNotTo",
        "flatMap", "any", "none", "all", "count", "contains", "asSequence",
        "onEach", "onEachIndexed",
        "maxBy", "minBy", "maxByOrNull", "minByOrNull",
        "maxOf", "minOf", "maxOfOrNull", "minOfOrNull",
        "maxWith", "minWith", "maxWithOrNull", "minWithOrNull",
        "maxOfWith", "minOfWith", "maxOfWithOrNull", "minOfWithOrNull",
    ]

    /// Iterable filter-family names that also exist on the `Map` surface.
    private static let mapFilterFamilyHOFNames: Set<String> = ["filter", "filterNot", "filterTo", "filterNotTo"]
    private static let mutableListOnlyCollectionHOFNames: Set<String> = ["sort", "sortBy", "sortByDescending", "sortWith"]

    private static let iterableMaxFamilyNames: Set<String> = [
        "max", "maxBy", "maxByOrNull", "maxOf", "maxOfOrNull",
        "maxOfWith", "maxOfWithOrNull", "maxOrNull", "maxWith", "maxWithOrNull",
    ]

    static let destinationCollectionHOFs: Set<String> = [
        "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo",
        "mapIndexedTo", "mapIndexedNotNullTo", "flatMapIndexedTo", "associateTo",
        "filterIndexedTo", "mapKeysTo", "mapValuesTo",
    ]

    static let sourceBackedListFilterNames: Set<String> = ["filter", "filterNot", "filterIndexed"]

    static let iterableSourceHOFNames: Set<String> = [
        "filter",
        "partition",
        "single",
        "singleOrNull",
        "reduce",
        "reduceIndexed",
        "reduceRight",
        "reduceRightIndexed",
        "reduceRightOrNull",
        "reduceRightIndexedOrNull",
        "sumBy",
        "sumByDouble",
    ]

    func tryInferMemberCallCollectionFlowSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        // Primitive-array source members are bundled Kotlin extensions, not collection or
        // sequence operations. Unsigned arrays currently also classify as
        // synthetic sequences, so let exact primitive-array source lookup run
        // before the generic collection-flow fast path.
        if !collectPrimitiveArraySourceMembers(
            named: calleeName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }
        if !collectArraySourceBackedCandidates(
            named: calleeName,
            receiverType: receiverType,
            ctx: ctx,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }
        // Defer inference of lambda arguments for collection HOFs so that the
        // contextual function type (and thus implicit `it`) is available.
        // Fallback for receivers that were never routed through a `flow { }`/operator
        // call (e.g. a user function declared `fun f(): Flow<Int>`), so the
        // `isFlowExpr`/`isFlowSymbol` bindings above were never marked. Recover the
        // same information directly from the receiver's inferred class type.
        let flowClassSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlinx"), interner.intern("coroutines"),
            interner.intern("flow"), interner.intern("Flow"),
        ])
        let receiverFlowClassType: ClassType? = if let flowClassSymbol,
                                                    case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                    classType.classSymbol == flowClassSymbol
        {
            classType
        } else {
            nil
        }
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverID) {
            true
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else if receiverFlowClassType != nil {
            true
        } else {
            false
        }
        if isFlowReceiver, calleeName == interner.intern("collect") {
            let flowPackage = [interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("flow")]
            if sema.bundledIndex.contains(
                ownerFQName: flowPackage + [interner.intern("Flow")], name: calleeName, arity: args.count
            ) || sema.symbols.lookupAll(fqName: flowPackage + [calleeName]).contains(where: {
                sema.symbols.isSourceBackedSymbol($0)
            }) {
                return nil
            }
        }
        let flowElementType: TypeID = if let elementType = sema.bindings.flowElementType(forExpr: receiverID) {
            elementType
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  let elementType = sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else if let firstArg = receiverFlowClassType?.args.first {
            switch firstArg {
            case let .invariant(t), let .out(t), let .in(t):
                t
            case .star:
                sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        let isFlowHOF = isFlowReceiver && Self.flowHOFNames.contains(interner.resolve(calleeName))
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        let receiverClassification = receiverClassifier.classify(
            receiverID: receiverID,
            receiverType: receiverType,
            ast: ast
        )
        let isCollectionReceiver = receiverClassification.isCollectionReceiver
        let isIterableReceiver = receiverClassification.isIterableReceiver
        let isArrayReceiver = receiverClassification.isArrayReceiver
        let isMapReceiver = receiverClassification.isMapReceiver
        let isMutableListReceiver = receiverClassification.isMutableListReceiver
        let isListReceiver = receiverClassification.isListReceiver
        let isListFactoryReceiver = receiverClassification.isListFactoryReceiver
        let isSyntheticSequenceReceiver = receiverClassification.isSyntheticSequenceReceiver
        let isSequenceReceiver = receiverClassification.isSequenceReceiver
        let isSetReceiver = receiverClassification.isSetReceiver
        let isEnumEntriesReceiver: Bool = {
            guard let (_, symbol) = resolveClassTypeSymbol(
                sema.types.makeNonNullable(receiverType),
                sema: sema
            ) else {
                return false
            }
            return symbol.fqName == knownNames.kotlinEnumsEnumEntriesFQName
        }()
        let isStringReceiver = sema.types.isSubtype(
            sema.types.makeNonNullable(receiverType),
            sema.types.stringType
        ) || isSyntheticStringLikeType(
            sema.types.makeNonNullable(receiverType),
            sema: sema
        )
        // KSP-979: only the plain Iterable surface and nominal user-defined
        // Iterable subtypes use the new source-backed index family. Concrete
        // collection receivers retain their existing owner-specific paths.
        let isIterableIndexReceiver = !isSequenceReceiver
            && !receiverClassifier.isCollectionLikeType(receiverType)
            && receiverClassifier.isNominalIterableType(receiverType)
        // Range/Progression aggregates have an independent runtime dispatch
        // family. Keep that ownership out of the Iterable source migration.
        let isRangeReceiver = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) != nil
        let isULongProgressionFirstLastCall = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) == .ulongProgression
            && args.isEmpty
            && ["first", "firstOrNull", "last", "lastOrNull"].contains(interner.resolve(calleeName))
        var activeCollectionHOFNames = Self.collectionHOFNames
        // zip is source-backed. Regular overload resolution must validate the
        // other collection/Sequence argument and respect user extensions.
        activeCollectionHOFNames.remove("zip")
        if !isMutableListReceiver {
            activeCollectionHOFNames.subtract(Self.mutableListOnlyCollectionHOFNames)
        }
        if !isSequenceReceiver {
            if !isIterableReceiver
                || receiverClassification.isListReceiver
                || receiverClassification.isSetReceiver
                || receiverClassification.isMapReceiver
            {
                activeCollectionHOFNames.remove("flatMapIndexed")
            }
        } else {
            activeCollectionHOFNames.remove("mapIndexedNotNull")
            activeCollectionHOFNames.remove("dropLastWhile")
            // These eager operations are unavailable on Kotlin Sequence.
            activeCollectionHOFNames.remove("takeLastWhile")
            activeCollectionHOFNames.remove("reversed")
            // KUU-1413: kotlin.sequences has no reduceRight family — a
            // one-pass Sequence cannot fold from the right. Skip the fast
            // path so regular overload resolution reports SEMA-0024 like
            // kotlinc's unresolved reference.
            activeCollectionHOFNames.remove("reduceRight")
            activeCollectionHOFNames.remove("reduceRightIndexed")
            activeCollectionHOFNames.remove("reduceRightOrNull")
            activeCollectionHOFNames.remove("reduceRightIndexedOrNull")
            // Sequence.flatMapTo/flatMapIndexedTo have Iterable- and
            // Sequence-return overloads. Let regular overload resolution use
            // the lambda return type instead of the single-shape destination
            // fast path below, which otherwise binds the first declaration.
            activeCollectionHOFNames.remove("flatMapTo")
            activeCollectionHOFNames.remove("flatMapIndexedTo")
            // KSP-1353/1354: Sequence.maxOfWith/minOfWith/maxOfWithOrNull/
            // minOfWithOrNull are now bundled Kotlin source. The fast path
            // below (case "maxOfWith", "minOfWith", ...) has no Sequence
            // binding branch for this family — bindBundledListSourceFunction
            // only binds a List receiver — so for a Sequence receiver the
            // call was left unresolved by this fast path and fell through to
            // the legacy kk_list_maxOfWith-family fallback at KIR lowering
            // (undefined symbol, since that bridge was never implemented for
            // Sequence). Drop these names here so a Sequence receiver skips
            // the fast path entirely and regular overload resolution picks
            // the source-backed declarations instead, the same way KSP-1345
            // did for flatMapTo/flatMapIndexedTo above.
            activeCollectionHOFNames.remove("maxOfWith")
            activeCollectionHOFNames.remove("maxOfWithOrNull")
            activeCollectionHOFNames.remove("minOfWith")
            activeCollectionHOFNames.remove("minOfWithOrNull")
        }
        if isMapReceiver {
            // KUU-1362: Map<K, V> is not an Iterable in Kotlin. Only names on
            // the bundled Map surface may take the collection fast path;
            // anything else (filterNotNull, fold, first, groupBy, ...) falls
            // through to regular overload resolution and reports SEMA-0024
            // instead of lowering to a phantom callee (LINK-0001).
            activeCollectionHOFNames.formIntersection(Self.mapCollectionHOFNames)
        }
        let calleeStr = interner.resolve(calleeName)
        if ["indexOf", "lastIndexOf", "subList"].contains(calleeStr),
           let listOwner = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsListFQName),
           driver.helpers.allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols).contains(where: {
               sema.types.isNominalSubtypeSymbol($0, of: listOwner)
           })
        {
            return nil
        }
        let isIterableIndexFamilyHOF = ["indexOf", "indexOfFirst", "indexOfLast"].contains(calleeStr)
        // KSP-983: a nominal Iterable receiver must use the exact bundled
        // Iterable max-family declarations. Let regular overload resolution
        // select the Comparable/Float/Double and lambda-return overloads;
        // concrete List/Set/Map/Sequence paths remain under their own owners.
        if Self.iterableMaxFamilyNames.contains(calleeStr),
           (isCollectionReceiver || isIterableReceiver),
           !isSequenceReceiver,
           !isSetReceiver,
           !isMapReceiver,
           !isArrayReceiver,
           !receiverClassifier.isConcreteListLikeType(receiverType)
        {
            return nil
        }
        let isIterableFilterFamilyHOF = [
            "filter", "filterIndexed", "filterIndexedTo", "filterIsInstance", "filterIsInstanceTo",
            "filterNot", "filterNotNull", "filterNotNullTo", "filterNotTo", "filterTo",
        ].contains(calleeStr)
            && (!isMapReceiver || Self.mapFilterFamilyHOFNames.contains(calleeStr))
        let isCollectionHOF = (activeCollectionHOFNames.contains(calleeStr) || isIterableFilterFamilyHOF)
            && (isCollectionReceiver
                || isSequenceReceiver
                || (isIterableIndexFamilyHOF && isIterableIndexReceiver)
                || (isIterableFilterFamilyHOF && isIterableReceiver)
                || (calleeStr == "none" && isIterableReceiver)
                || (calleeStr == "asSequence" && isIterableReceiver)
                || ((calleeStr == "runningReduce" || calleeStr == "runningReduceIndexed") && isIterableReceiver))
            && !isULongProgressionFirstLastCall
            && !(calleeStr == "binarySearch"
                && isArrayReceiver)
            // KUU-1432: every destination HOF takes exactly two arguments
            // (destination + lambda). The destination arm below only handles
            // the arity-2 shape, so a call at any other arity fell through to
            // `default:` with a result type but no callee and lowered to a
            // phantom `_filterTo`-style symbol (LINK-0001). Skip the fast path
            // so regular overload resolution reports the missing argument
            // (SEMA-0002/SEMA-0024), matching kotlinc's "no value passed for
            // parameter" rejection.
            && !(Self.destinationCollectionHOFs.contains(calleeStr) && args.count != 2)

        // KSP-957: the generic Iterable/Map on-family declarations are real
        // source-backed overloads. Let regular overload resolution select
        // them; the collection fast path only knows the legacy List/Sequence
        // shapes and would otherwise erase the receiver-preserving return type.
        let isSourceBackedGenericOnEach = !isSequenceReceiver
            && !isArrayReceiver
            && !isListReceiver
            && !isStringReceiver
            && (isCollectionReceiver || isIterableReceiver || isMapReceiver)
            && (calleeStr == "onEach" || calleeStr == "onEachIndexed")
        // KSP-969: bind the generic Iterable drop family for a statically
        // Iterable receiver as well as concrete collection receivers. List
        // overloads are attempted first so the more specific source-backed
        // declaration keeps winning for List values.
        let isIterableDropFamily = !isSequenceReceiver
            && (calleeStr == "drop" || calleeStr == "dropWhile")
            && (isCollectionReceiver || isIterableReceiver)
        let flow = MemberCallCollectionFlowContext(
            checker: self,
            driver: driver,
            id: id,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall,
            ast: ast,
            sema: sema,
            interner: interner,
            knownNames: knownNames,
            receiverType: receiverType,
            receiverClassifier: receiverClassifier,
            receiverClassification: receiverClassification,
            isCollectionReceiver: isCollectionReceiver,
            isIterableReceiver: isIterableReceiver,
            isArrayReceiver: isArrayReceiver,
            isMapReceiver: isMapReceiver,
            isMutableListReceiver: isMutableListReceiver,
            isListReceiver: isListReceiver,
            isListFactoryReceiver: isListFactoryReceiver,
            isSyntheticSequenceReceiver: isSyntheticSequenceReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isSetReceiver: isSetReceiver,
            isEnumEntriesReceiver: isEnumEntriesReceiver,
            isIterableIndexReceiver: isIterableIndexReceiver,
            isRangeReceiver: isRangeReceiver,
            calleeStr: calleeStr,
            isIterableIndexFamilyHOF: isIterableIndexFamilyHOF,
            isIterableFilterFamilyHOF: isIterableFilterFamilyHOF,
            isCollectionHOF: isCollectionHOF,
            isSourceBackedGenericOnEach: isSourceBackedGenericOnEach,
            isIterableDropFamily: isIterableDropFamily
        )

        if let inferredType = flow.inferIterableDropFamilySpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferIterableElementFamilySpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }

        if let mapIteratorType = flow.bindBundledMapIteratorSourceFunction(locals: &locals) {
            sema.bindings.bindExprType(id, type: mapIteratorType)
            return mapIteratorType
        }

        if let inferredType = flow.inferMutableListMemberSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferAsFlowMemberSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferZipMemberSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterIsInstanceSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferToCollectionSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterIsInstanceToSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterNotNullSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferFilterNotNullToSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferBinarySearchLambdaSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferGenericOnEachSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }
        if let inferredType = flow.inferCollectionHOFSpecial(locals: &locals) { return inferredType }
        if flow.didReturnNil { return nil }

        if flow.didReturnNil { return nil }

        if isFlowHOF,
           let lambdaArg = args.first?.expr,
           let lambdaExpr = ast.arena.expr(lambdaArg),
           lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(lambdaArg)
        }

        // KSP-499 Stage 3: a real bundled/user Kotlin declaration for this
        // exact (Flow owner, member name, arity) takes priority over the
        // hard-coded Flow intrinsic dispatch below — mirrors the declaration
        // priority rule already established for synthetic stub registration
        // (BundledDeclarationIndex / KSP-001-003). Without this, migrating a
        // Flow operator to real Kotlin source would compile but never run:
        // this special-case would keep intercepting the call by name.
        let flowOwnerFQNameForPriorityCheck: [InternedString]? = {
            guard case let .classType(classType) = sema.types.kind(of: receiverType),
                  let ownerSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            return ownerSymbol.fqName
        }()
        let hasBundledFlowDeclaration = flowOwnerFQNameForPriorityCheck.map {
            sema.bundledIndex.contains(
                ownerFQName: $0,
                name: calleeName
            )
        } ?? false
        if isFlowReceiver,
           hasBundledFlowDeclaration,
           !["transform", "takeWhile", "dropWhile", "catch", "retry", "retryWhen"].contains(interner.resolve(calleeName)),
           let bundledFlowType = tryBuiltinFlowMemberCall(
               id,
               calleeName: calleeName,
               receiverElementType: flowElementType,
               args: args,
               safeCall: safeCall,
               ast: ast,
               sema: sema,
               ctx: ctx,
               locals: &locals
           )
        {
            // The builtin path above supplies the contextual lambda types and
            // Flow element-type tracking. Once a Flow operator has a bundled
            // Kotlin declaration, retain that source-backed symbol as the
            // call target so lowering cannot fall back to a name-only bridge.
            let flowPackageFQName = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("flow"),
                calleeName,
            ]
            if let bundledCallee = sema.symbols.lookupAll(fqName: flowPackageFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.parameterTypes.count == args.count && signature.receiverType != nil
            }),
               let signature = sema.symbols.functionSignature(for: bundledCallee)
            {
                func typeID(from argument: TypeArg) -> TypeID {
                    switch argument {
                    case let .invariant(type), let .out(type), let .in(type):
                        type
                    case .star:
                        sema.types.anyType
                    }
                }

                func inferTypeParameters(
                    declared: TypeID,
                    actual: TypeID,
                    substitutions: inout [SymbolID: TypeID]
                ) {
                    switch sema.types.kind(of: declared) {
                    case let .typeParam(typeParameter):
                        substitutions[typeParameter.symbol] = actual
                    case let .classType(declaredClass):
                        guard case let .classType(actualClass) = sema.types.kind(of: sema.types.makeNonNullable(actual)),
                              declaredClass.classSymbol == actualClass.classSymbol
                        else {
                            return
                        }
                        for (declaredArgument, actualArgument) in zip(declaredClass.args, actualClass.args) {
                            inferTypeParameters(
                                declared: typeID(from: declaredArgument),
                                actual: typeID(from: actualArgument),
                                substitutions: &substitutions
                            )
                        }
                    case let .functionType(declaredFunction):
                        guard case let .functionType(actualFunction) = sema.types.kind(of: actual) else {
                            return
                        }
                        if let declaredReceiver = declaredFunction.receiver,
                           let actualReceiver = actualFunction.receiver
                        {
                            inferTypeParameters(
                                declared: declaredReceiver,
                                actual: actualReceiver,
                                substitutions: &substitutions
                            )
                        }
                        for (declaredParameter, actualParameter) in zip(declaredFunction.params, actualFunction.params) {
                            inferTypeParameters(
                                declared: declaredParameter,
                                actual: actualParameter,
                                substitutions: &substitutions
                            )
                        }
                        inferTypeParameters(
                            declared: declaredFunction.returnType,
                            actual: actualFunction.returnType,
                            substitutions: &substitutions
                        )
                    default:
                        return
                    }
                }

                var substitutions: [SymbolID: TypeID] = [:]
                if let declaredReceiver = signature.receiverType {
                    inferTypeParameters(
                        declared: declaredReceiver,
                        actual: receiverType,
                        substitutions: &substitutions
                    )
                }
                for (index, parameterType) in signature.parameterTypes.enumerated()
                where index < args.count {
                    let actualType = sema.bindings.exprType(for: args[index].expr)
                        ?? driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals)
                    inferTypeParameters(
                        declared: parameterType,
                        actual: actualType,
                        substitutions: &substitutions
                    )
                }
                let typeArguments = signature.typeParameterSymbols.map { substitutions[$0] ?? sema.types.anyType }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: bundledCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(bundledCallee))
                driver.helpers.checkOptIn(
                    for: bundledCallee,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            return bundledFlowType
        }
        if isFlowReceiver,
           !hasBundledFlowDeclaration,
           let builtinFlowType = tryBuiltinFlowMemberCall(
               id,
               calleeName: calleeName,
               receiverElementType: flowElementType,
               args: args,
               safeCall: safeCall,
               ast: ast,
               sema: sema,
               ctx: ctx,
               locals: &locals
           )
        {
            return builtinFlowType
        }
        return nil
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
