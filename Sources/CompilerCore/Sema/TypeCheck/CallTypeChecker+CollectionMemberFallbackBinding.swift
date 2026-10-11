// swiftlint:disable file_length
import RuntimeABI

/// Member-call fallback binding path for Collection-typed receivers:
/// bundled Kotlin source-extension candidates and their binding,
/// callee resolution/validation, and parameter mapping.
///
/// Split out from `CallTypeChecker+CollectionMemberFallback.swift`.
extension CallTypeChecker {
    func tryCollectionMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        expectedType: TypeID? = nil,
        // Only set by call sites reached when ordinary symbol lookup already
        // found zero candidates (see CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift).
        // Call sites reached while real overload candidates exist (e.g.
        // Iterable.reduceRightIndexed, which is a registered symbol) must NOT
        // set this, or this fallback would short-circuit ahead of the normal
        // overload resolver for members it does not model precisely.
        admitNominalIterableReceiver: Bool = false,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        guard calleeName != knownNames.contains else { return nil }

        let memberName = interner.resolve(calleeName)
        if sema.bindings.exprTypes[receiverID] == nil {
            _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        }
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        if calleeName == knownNames.containsAll {
            // Expression markers also admit Iterable and Sequence values here,
            // but containsAll belongs only to Collection and its subtypes.
            guard let collectionSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsCollectionFQName),
                  driver.helpers.allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols).contains(where: {
                      sema.types.isNominalSubtypeSymbol($0, of: collectionSymbol)
                  })
            else {
                return nil
            }
        }
        let sourceLevelRangeReceiverType = sourceLevelRangeMemberLookupType(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        )
        let receiverClassification = receiverClassifier.classify(receiverID: receiverID)
        // KUU-569: Int range expressions use their scalar runtime representation
        // during Sema, while IntRange/IntProgression are nominal Iterable
        // implementations. Recover that source-level conformance only in the
        // no-candidate collection fallback; exact range extensions have already
        // had priority in tryRangeMemberFallback/regular resolution.
        let rangeReceiverKind = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        )
        let isIntRangeOrProgression = rangeReceiverKind == .intRange
            || rangeReceiverKind == .intProgression
        let isCharRangeJoinReceiver = rangeReceiverKind == .charRange
            && memberName == "joinToString"
        let isRangeIterableReceiver = isIntRangeOrProgression
            && isKUU569RangeIterableMember(memberName, argCount: args.count)
            && (sourceLevelRangeReceiverType.map {
                receiverClassifier.isNominalIterableType($0)
            } ?? false)
        let rangeIterableSourceCandidates = isRangeIterableReceiver
            ? rangeIterableSourceExtensionCandidates(
                named: calleeName,
                sema: sema,
                interner: interner
            )
            : []
        let scopedCharRangeJoinCandidates = isCharRangeJoinReceiver
            ? sourceLevelRangeReceiverType.map {
                collectScopedRangeUserExtensionCandidates(
                    named: calleeName,
                    receiverType: $0,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                )
            } ?? []
            : []
        let charRangeJoinSourceCandidates = isCharRangeJoinReceiver
            ? charRangeJoinSourceExtensionCandidates(
                named: calleeName,
                sema: sema,
                interner: interner
            )
            : []
        let isArrayReceiver = receiverClassification.isArrayReceiver
        let isIterableWindowedTransformCall: Bool = {
            guard memberName == "windowed",
                  (2...4).contains(args.count),
                  receiverClassification.isIterableReceiver,
                  let lastArgExpr = args.last?.expr,
                  let lastArgExprNode = ctx.ast.arena.expr(lastArgExpr)
            else {
                return false
            }
            return lastArgExprNode.isLambdaOrCallableRef
        }()
        let isIterableChunkedTransformCall: Bool = {
            guard memberName == "chunked",
                  args.count == 2,
                  receiverClassification.isIterableReceiver,
                  let lastArgExpr = args.last?.expr,
                  let lastArgExprNode = ctx.ast.arena.expr(lastArgExpr)
            else {
                return false
            }
            return lastArgExprNode.isLambdaOrCallableRef
        }()
        let isIterableFirstNotNullOfCall: Bool = {
            guard memberName == "firstNotNullOf",
                  args.count == 1,
                  receiverClassification.isIterableReceiver || isArrayReceiver,
                  let firstArgExpr = args.first?.expr,
                  let firstArgNode = ctx.ast.arena.expr(firstArgExpr)
            else {
                return false
            }
            return firstArgNode.isLambdaOrCallableRef
        }()
        let isIterableFirstNotNullOfOrNullCall: Bool = {
            guard memberName == "firstNotNullOfOrNull",
                  args.count == 1,
                  receiverClassification.isIterableReceiver || isArrayReceiver,
                  let firstArgExpr = args.first?.expr,
                  let firstArgNode = ctx.ast.arena.expr(firstArgExpr)
            else {
                return false
            }
            return firstArgNode.isLambdaOrCallableRef
        }()
        let isIterableRequireNoNullsCall =
            memberName == "requireNoNulls"
            && args.isEmpty
            && receiverClassification.isIterableReceiver
        let isCollectionReceiver = receiverClassification.isCollectionReceiver
        let isSequenceReceiver = receiverClassification.isSequenceReceiver
        // A receiver whose static type is nominally `Iterable<T>` (e.g. a local
        // variable explicitly typed `Iterable<T>`, or a function parameter typed
        // `Iterable<T>`) but isn't otherwise recognized as collection/sequence-like
        // must still be admitted when ordinary symbol lookup found no candidates at
        // all (isCollectionReceiver/isSequenceReceiver rely on either a concrete
        // List/Set/Map/Sequence type or the isCollectionExpr propagation heuristic,
        // which only fires for a fixed set of collection-factory call forms like
        // listOf(...), not arbitrary functions returning List<T>). Restricted to the
        // no-candidates case so members already resolved as real Iterable-owned
        // symbols (e.g. Iterable.reduceRightIndexed) keep going through the normal
        // overload resolver instead of this fallback's approximate typing.
        let admitIterableReceiver = admitNominalIterableReceiver
            && (receiverClassification.isIterableReceiver
                || isRangeIterableReceiver
                || isCharRangeJoinReceiver)
        // Allow arrays to fall through to collection fallback only when
        // tryArrayMemberFallback does not handle the member (isSupportedArrayMember returns false).
        guard !isClassNameReceiver,
              !(isArrayReceiver && isSupportedArrayMember(memberName)),
              isCollectionReceiver
                || isSequenceReceiver
                // Array factories intentionally stay out of the generic
                // collection-expression marker so List-only extensions do not
                // receive an Array runtime representation. Keep the safe
                // conversion members available from their static Array type.
                || (isArrayReceiver && (memberName == "asSequence" || memberName == "asIterable" || memberName == "joinToString"))
                || admitIterableReceiver
                || isIterableWindowedTransformCall
                || isIterableChunkedTransformCall
                || isIterableFirstNotNullOfCall
                || isIterableFirstNotNullOfOrNullCall
                || isIterableRequireNoNullsCall
        else {
            return nil
        }

        let isIterableReceiver = receiverClassification.isIterableReceiver
            || isRangeIterableReceiver
            || isCharRangeJoinReceiver
        let isMapReceiver = receiverClassification.isMapReceiver
        let isSetReceiver = receiverClassification.isSetReceiver
        let isMutableCollectionReceiverFlag = receiverClassification.isMutableCollectionReceiver
        let isMutableListReceiver = receiverClassification.isMutableListReceiver
        let isMutableSetReceiver = receiverClassification.isMutableSetReceiver
        let isMutableMapReceiver = receiverClassification.isMutableMapReceiver
        let isListReceiver = receiverClassification.isListReceiver
        if memberName == "average", isIterableReceiver, !isSequenceReceiver, !isArrayReceiver {
            let receiverElementType = collectionFallbackElementType(
                receiverID: receiverID,
                sema: sema,
                interner: interner
            )
            let numericAverageElementTypes: Set<TypeID> = [
                sema.types.byteType,
                sema.types.shortType,
                sema.types.intType,
                sema.types.longType,
                sema.types.floatType,
                sema.types.doubleType,
            ]
            // Kotlin only defines Iterable.average() for non-null numeric
            // element types. Keep the legacy fallback from accepting a
            // source-incompatible receiver when no source candidate matched.
            guard numericAverageElementTypes.contains(receiverElementType) else {
                return nil
            }
        }
        let addAllFirstArgumentExpr: ExprID? = if memberName == "addAll",
                                                  args.count == 1,
                                                  let firstArg = args.first {
            firstArg.expr
        } else {
            nil
        }
        if let addAllFirstArgumentExpr,
           sema.bindings.exprTypes[addAllFirstArgumentExpr] == nil
        {
            _ = driver.inferExpr(addAllFirstArgumentExpr, ctx: ctx, locals: &locals)
        }
        let addAllArgumentClassification = addAllFirstArgumentExpr.map {
            receiverClassifier.classify(receiverID: $0)
        }
        let isAddAllArrayArgument = addAllArgumentClassification?.isArrayReceiver ?? false
        let addAllFirstArgumentType = addAllFirstArgumentExpr.flatMap { sema.bindings.exprTypes[$0] }
        let isAddAllSequenceArgument: Bool = if let firstArgType = addAllFirstArgumentType {
            receiverClassifier.isSequenceLikeType(firstArgType)
        } else {
            false
        }
        let isAddAllIterableArgument: Bool = if let firstArgType = addAllFirstArgumentType {
            addAllArgumentClassification?.isIterableReceiver == true
                && !receiverClassifier.isCollectionLikeType(firstArgType)
                && !receiverClassifier.isSequenceLikeType(firstArgType)
        } else {
            false
        }

        // KUU-566: MutableSet predicate mutations are MutableIterable source
        // extensions, not the collection-valued synthetic set members. Bind
        // them before the generic fallback so the predicate element type is
        // available while resolving MutableMap.MutableEntry.key/value.
        if let sourceType = bindMutableSetPredicateSourceExtension(
            exprID: id,
            memberName: calleeName,
            receiverID: receiverID,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
        ) {
            return sourceType
        }

        // KSP-1019: MutableCollection's Iterable/Sequence/Array overloads are
        // top-level Kotlin extensions, not interface members. Bind the exact
        // source declaration before the generic collection fallback can select
        // the unrelated Collection member or a runtime bridge. MutableList
        // shares these migrated extensions, while MutableSet retains its
        // residual member and synthetic paths.
        if let sourceType = bindMutableCollectionSourceExtension(
            exprID: id,
            memberName: calleeName,
            receiverID: receiverID,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
        ) {
            return sourceType
        }

        let isSupportedLegacyCollectionFallback = isSupportedCollectionFallbackMember(
            calleeName,
            isIterableReceiver: isIterableReceiver,
            isListReceiver: isListReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isMutableCollectionReceiver: isMutableCollectionReceiverFlag,
            isMutableListReceiver: isMutableListReceiver,
            isMutableSetReceiver: isMutableSetReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            isAddAllArrayArgument: isAddAllArrayArgument,
            isAddAllSequenceArgument: isAddAllSequenceArgument,
            isAddAllIterableArgument: isAddAllIterableArgument,
            interner: interner
        ) && isValidCollectionFallbackArity(
            calleeName,
            argCount: args.count,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isListReceiver: isListReceiver,
            isMutableCollectionReceiver: isMutableCollectionReceiverFlag,
            isMutableMapReceiver: isMutableMapReceiver,
            isMutableSetReceiver: isMutableSetReceiver,
            isMutableListReceiver: isMutableListReceiver,
            isAddAllArrayArgument: isAddAllArrayArgument,
            isAddAllSequenceArgument: isAddAllSequenceArgument,
            isAddAllIterableArgument: isAddAllIterableArgument,
            interner: interner
        )
        guard !rangeIterableSourceCandidates.isEmpty
            || !scopedCharRangeJoinCandidates.isEmpty
            || !charRangeJoinSourceCandidates.isEmpty
            || isSupportedLegacyCollectionFallback
        else {
            return nil
        }

        // Provide contextual function type for collection HOF lambda inference.
        let receiverElementType = collectionFallbackElementType(receiverID: receiverID, sema: sema, interner: interner)

        // flatten() is only valid on List<List<T>>. Reject when the element type
        // is a KNOWN non-collection (e.g. Int).  If the element type is Any we
        // cannot be sure — it may be List<Any> wrapping real lists at runtime,
        // so we let it through to preserve the pre-migration behaviour.
        if calleeName == knownNames.flatten, !isSequenceReceiver,
           receiverElementType != sema.types.anyType,
           !receiverClassifier.isCollectionLikeType(receiverElementType) {
            return nil
        }

        if isRangeIterableReceiver,
           let expectation = rangeIterableSourceLambdaExpectation(
               memberName: memberName,
               argCount: args.count,
               receiverElementType: receiverElementType,
               sema: sema
           )
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }
        if let expectation = collectionFallbackLambdaExpectation(
            memberName: calleeName,
            argCount: args.count,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            args: args,
            ctx: ctx,
            interner: interner,
            sema: sema
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }
        if (memberName == "add" || memberName == "remove"), args.count == 1 {
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: receiverElementType
            )
        }
        if memberName == "addAll", args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        }
        if memberName == "putAll", args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        }

        if !rangeIterableSourceCandidates.isEmpty {
            return tryBindRangeIterableSourceExtension(
                id,
                calleeName: calleeName,
                receiverID: receiverID,
                candidates: rangeIterableSourceCandidates,
                receiverElementType: receiverElementType,
                args: args,
                safeCall: safeCall,
                expectedType: expectedType,
                ctx: ctx,
                locals: &locals
            )
        }
        if let sourceLevelRangeReceiverType {
            if !scopedCharRangeJoinCandidates.isEmpty,
               let scopedType = tryBindCharRangeJoinSourceExtension(
                   id,
                   calleeName: calleeName,
                   receiverID: receiverID,
                   candidates: scopedCharRangeJoinCandidates,
                   receiverType: sourceLevelRangeReceiverType,
                   args: args,
                   safeCall: safeCall,
                   expectedType: expectedType,
                   ctx: ctx,
                   locals: &locals
               )
            {
                return scopedType
            }
            if !charRangeJoinSourceCandidates.isEmpty {
                return tryBindCharRangeJoinSourceExtension(
                    id,
                    calleeName: calleeName,
                    receiverID: receiverID,
                    candidates: charRangeJoinSourceCandidates,
                    receiverType: sourceLevelRangeReceiverType,
                    args: args,
                    safeCall: safeCall,
                    expectedType: expectedType,
                    ctx: ctx,
                    locals: &locals
                )
            }
        }

        if isCollectionReturningMember(
            calleeName,
            isMapReceiver: isMapReceiver,
            isListReceiver: isListReceiver,
            isSetReceiver: isSetReceiver,
            interner: interner
        ) {
            sema.bindings.markCollectionExpr(id)
        }

        let didBindListFilterNotNullSource: Bool = {
            guard memberName == "filterNotNull",
                  args.isEmpty,
                  isListReceiver
            else {
                return false
            }
            let sourceFQName = knownNames.kotlinCollectionsPackage + [calleeName]
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.isEmpty,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                return receiverClassifier.isConcreteListLikeType(signatureReceiver)
            }) else {
                return false
            }
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: [sema.types.makeNonNullable(receiverElementType)],
                    parameterMapping: [:]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            return true
        }()

        let didBindListZipSource: Bool = {
            guard memberName == "zip",
                  !args.isEmpty,
                  !isSequenceReceiver,
                  isCollectionReceiver
            else {
                return false
            }
            let otherType = sema.bindings.exprTypes[args[0].expr]
                ?? driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let otherElementType: TypeID
            if case let .classType(otherClassType) = sema.types.kind(of: sema.types.makeNonNullable(otherType)),
               let firstArg = otherClassType.args.first
            {
                otherElementType = switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                otherElementType = sema.types.anyType
            }
            let typeArguments: [TypeID]
            if args.count >= 2,
               let transformType = sema.bindings.exprTypes[args[1].expr],
               case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType))
            {
                typeArguments = [receiverElementType, otherElementType, fnType.returnType]
            } else if args.count >= 2 {
                typeArguments = [receiverElementType, otherElementType, sema.types.anyType]
            } else {
                typeArguments = [receiverElementType, otherElementType]
            }

            let sourceFQName = knownNames.kotlinCollectionsPackage + [calleeName]
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                if isCollectionLikeType(signatureReceiver, sema: sema, interner: interner) {
                    return true
                }
                guard let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema) else {
                    return false
                }
                return receiverSymbol.fqName == knownNames.kotlinCollectionsIterableFQName
            }) else {
                return false
            }
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            return true
        }()

        if !didBindListFilterNotNullSource,
           !didBindListZipSource,
           let fallbackCallee = resolveCollectionFallbackCallee(
            memberName: calleeName,
            receiverID: receiverID,
            argExprs: args.map(\.expr),
            argLabels: args.map(\.label),
            argCount: args.count,
            ctx: ctx,
            sema: sema,
            interner: interner
        ) {
            if let invalidFallbackType = validateCollectionFallbackCallee(
                fallbackCallee,
                exprID: id,
                calleeName: calleeName,
                safeCall: safeCall,
                receiverID: receiverID,
                ctx: ctx
            ) {
                return invalidFallbackType
            }
            let parameterMapping = buildCollectionFallbackParameterMapping(
                args: args,
                fallbackCallee: fallbackCallee,
                sema: sema
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: fallbackCallee,
                    substitutedTypeArguments: [],
                    parameterMapping: parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
        }

        var resultType = collectionFallbackResultType(
            memberName: calleeName,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            isListReceiver: isListReceiver,
            isSetReceiver: isSetReceiver,
            isSequenceReceiver: isSequenceReceiver,
            // Real Kotlin declares a covariant `iterator(): MutableIterator<E>`
            // override on MutableIterable/MutableCollection (inherited by
            // MutableList/MutableSet) and `subList(...): MutableList<E>` on
            // MutableList. This fallback binds ahead of the normal overload
            // resolver for these well-known members (see the `!hasSourceBackedCandidate`
            // short-circuit in CallTypeChecker+MemberCallInferenceRegularResolution.swift),
            // so it must report the mutable-aware type itself.
            isMutableReceiver: isMutableCollectionReceiverFlag || isMutableListReceiver || isMutableSetReceiver,
            args: args,
            ctx: ctx,
            sema: sema,
            expectedType: expectedType,
            interner: interner
        )
        // When the receiver is Sequence, sequence-returning operations (map,
        // filter, etc.) should return Sequence<E> so the KIR builder's
        // sequence HOF handler recognises chained calls (STDLIB-471).
        if isSequenceReceiver,
           isCollectionReturningMember(calleeName, isMapReceiver: false, isListReceiver: false, isSetReceiver: false, interner: interner),
           resultType == sema.types.anyType
        {
            resultType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func rangeIterableSourceExtensionCandidates(
        named calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let knownNames = KnownCompilerNames(interner: interner)
        let kotlinCollections = knownNames.kotlinCollectionsPackage
        let kotlinSequences = knownNames.kotlinSequencesPackage
        let iterableFQName = knownNames.kotlinCollectionsIterableFQName
        guard let iterableSymbol = sema.symbols.lookup(fqName: iterableFQName) else {
            return []
        }
        return sema.symbols.lookupByShortName(calleeName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  let declaredReceiverSymbol = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(declaredReceiver),
                      types: sema.types
                  )
            else {
                return false
            }
            let package = Array(symbol.fqName.dropLast())
            return declaredReceiverSymbol == iterableSymbol
                && (package == kotlinCollections || package == kotlinSequences)
        }
    }

    private func isKUU569RangeIterableMember(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "elementAt", "indexOf", "lastIndexOf", "asIterable", "asSequence",
             "toSet", "toMutableList", "joinToString", "maxOrNull", "sumOf",
             "zip", "associateWith", "groupBy", "partition", "takeWhile",
             "dropWhile", "distinct", "sortedDescending", "flatMap", "intersect",
             "union", "subtract", "withIndex", "shuffled":
            return true
        case "count":
            // KUU-569 covers the predicate overload. Keep count() on its
            // existing range-specific route so this fix does not change
            // already-supported range members or their Golden ownership.
            return argCount == 1
        default:
            return false
        }
    }

    private func charRangeJoinSourceExtensionCandidates(
        named calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let knownNames = KnownCompilerNames(interner: interner)
        let package = knownNames.kotlinRangesPackage
        let charRangeFQName = knownNames.kotlinRangesCharRangeFQName
        guard let charRangeSymbol = sema.symbols.lookup(fqName: charRangeFQName) else {
            return []
        }
        return sema.symbols.lookupAll(fqName: package + [calleeName]).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  let declaredReceiverSymbol = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(declaredReceiver),
                      types: sema.types
                  )
            else {
                return false
            }
            return declaredReceiverSymbol == charRangeSymbol
        }
    }

    private func tryBindCharRangeJoinSourceExtension(
        _ id: ExprID,
        calleeName: InternedString,
        receiverID: ExprID,
        candidates: [SymbolID],
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let argumentTypes = args.map { argument in
            sema.bindings.exprType(for: argument.expr)
                ?? driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }
        guard let callRange = ctx.ast.arena.exprRange(id) ?? ctx.ast.arena.exprRange(receiverID) else {
            return nil
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: callRange,
                calleeName: calleeName,
                args: zip(args, argumentTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
            ),
            expectedType: expectedType,
            implicitReceiverType: receiverType,
            ctx: sema
        )
        guard resolved.diagnostic == nil,
              let chosen = resolved.chosenCallee
        else {
            return nil
        }
        let resultType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: resolved,
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func rangeIterableSourceLambdaExpectation(
        memberName: String,
        argCount: Int,
        receiverElementType: TypeID,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        guard argCount == 1 else {
            return nil
        }
        let returnType: TypeID
        switch memberName {
        case "takeWhile", "dropWhile":
            returnType = sema.types.booleanType
        case "sumOf", "associateWith", "groupBy", "flatMap":
            // Infer the body first, then re-infer with its concrete return type
            // before overload resolution so generic result types stay precise.
            returnType = sema.types.anyType
        default:
            return nil
        }
        return (
            argumentIndex: 0,
            expectedType: sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: returnType,
                isSuspend: false,
                nullability: .nonNull
            )))
        )
    }

    private func tryBindRangeIterableSourceExtension(
        _ id: ExprID,
        calleeName: InternedString,
        receiverID: ExprID,
        candidates: [SymbolID],
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        let iterableFQName = knownNames.kotlinCollectionsIterableFQName

        guard let iterableSymbol = sema.symbols.lookup(fqName: iterableFQName) else {
            return nil
        }

        let iterableReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(receiverElementType)],
            nullability: .nonNull
        )))
        let memberName = interner.resolve(calleeName)
        let lambdaBodyReturnType: TypeID? = if ["sumOf", "associateWith", "groupBy", "flatMap"]
            .contains(memberName),
            args.count == 1,
            let argument = ctx.ast.arena.expr(args[0].expr),
            argument.isLambdaOrCallableRef
        {
            inferredLambdaReturnType(argExpr: args[0].expr, ast: ctx.ast, sema: sema)
        } else {
            nil
        }
        if let lambdaBodyReturnType {
            let lambdaType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: lambdaBodyReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: lambdaType
            )
        }
        let argumentTypes = args.map { argument in
            sema.bindings.exprType(for: argument.expr)
                ?? driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }
        let resolutionCandidates: [SymbolID] = {
            guard memberName == "flatMap",
                  let lambdaBodyReturnType,
                  let sequenceSymbol = sema.symbols.lookup(fqName: knownNames.kotlinSequenceFQName)
            else {
                return candidates
            }
            let expectedReturnSymbol = ReceiverClassifier(sema: sema, interner: interner)
                .isSequenceLikeType(lambdaBodyReturnType)
                ? sequenceSymbol
                : iterableSymbol
            return candidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = signature.parameterTypes.first,
                      case let .functionType(functionType) = sema.types.kind(of: parameterType),
                      let returnSymbol = driver.helpers.nominalSymbol(
                          of: sema.types.makeNonNullable(functionType.returnType),
                          types: sema.types
                      )
                else {
                    return false
                }
                return returnSymbol == expectedReturnSymbol
            }
        }()
        guard let callRange = ctx.ast.arena.exprRange(id) ?? ctx.ast.arena.exprRange(receiverID) else {
            return nil
        }
        let call = CallExpr(
            range: callRange,
            calleeName: calleeName,
            args: zip(args, argumentTypes).map { argument, type in
                CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
            }
        )
        let resolved = ctx.resolver.resolveCall(
            candidates: resolutionCandidates,
            call: call,
            expectedType: expectedType,
            implicitReceiverType: iterableReceiverType,
            ctx: sema
        )
        guard resolved.diagnostic == nil,
              let chosen = resolved.chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let resultType = sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
        if isCollectionReturningMember(
            calleeName,
            isMapReceiver: false,
            isListReceiver: false,
            isSetReceiver: false,
            interner: interner
        ) {
            sema.bindings.markCollectionExpr(id)
        }
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func bindMutableCollectionSourceExtension(
        exprID: ExprID,
        memberName: InternedString,
        receiverID: ExprID,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        guard args.count == 1 else { return nil }
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard let (_, receiverSymbol) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(receiverType),
            sema: sema
        ) else {
            return nil
        }
        let receiverFQName = receiverSymbol.fqName
        guard receiverFQName == knownNames.kotlinCollectionsMutableCollectionFQName
            || receiverFQName == knownNames.kotlinCollectionsMutableListFQName
        else {
            return nil
        }

        guard memberName == knownNames.addAll || memberName == knownNames.removeAll || memberName == knownNames.retainAll else {
            return nil
        }
        let isMutableListReceiver = receiverFQName == knownNames.kotlinCollectionsMutableListFQName
        guard !isMutableListReceiver || memberName == knownNames.addAll else {
            return nil
        }

        let argument = args[0].expr
        if sema.bindings.exprTypes[argument] == nil {
            _ = driver.inferExpr(argument, ctx: ctx, locals: &locals)
        }
        let argumentType = sema.bindings.exprTypes[argument] ?? sema.types.anyType
        let classifier = ReceiverClassifier(sema: sema, interner: interner)
        var argumentNominalSymbols = driver.helpers.allNominalSymbols(
            of: sema.types.makeNonNullable(argumentType),
            types: sema.types,
            symbols: sema.symbols
        )
        var visitedArgumentSymbols = Set<SymbolID>(argumentNominalSymbols)
        var argumentSymbolIndex = 0
        while argumentSymbolIndex < argumentNominalSymbols.count {
            let symbol = argumentNominalSymbols[argumentSymbolIndex]
            argumentNominalSymbols.append(contentsOf: sema.symbols.directSupertypes(for: symbol).filter {
                visitedArgumentSymbols.insert($0).inserted
            })
            argumentSymbolIndex += 1
        }
        func hasNominalType(_ fqName: [InternedString]) -> Bool {
            argumentNominalSymbols.contains { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.fqName == fqName
            }
        }
        let parameterID: InternedString?
        if classifier.isArrayLikeType(argumentType)
            || hasNominalType(knownNames.kotlinArrayFQName)
        {
            parameterID = knownNames.array
        } else if classifier.isSequenceLikeType(argumentType)
                    || hasNominalType(knownNames.kotlinSequenceFQName)
        {
            parameterID = knownNames.sequence
        } else if classifier.isCollectionLikeType(argumentType)
                    || hasNominalType(knownNames.kotlinCollectionsCollectionFQName)
                    || hasNominalType(knownNames.kotlinCollectionsMutableCollectionFQName)
        {
            // Kotlin gives the MutableCollection member overload priority for
            // Collection arguments; the extension must not replace that call.
            parameterID = nil
        } else if classifier.isIterableLikeType(argumentType)
                    || hasNominalType(knownNames.kotlinCollectionsIterableFQName)
                    || hasNominalType(knownNames.kotlinCollectionsMutableIterableFQName)
        {
            parameterID = knownNames.iterable
        } else {
            parameterID = nil
        }
        guard let parameterID else {
            return nil
        }

        let sourceFQName = knownNames.kotlinCollectionsPackage + [memberName]
        let candidate = sema.symbols.lookupAll(fqName: sourceFQName).first { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  // Bundled source functions are non-synthetic; imported
                  // stdlib metadata carries the same declarations as
                  // synthetic + importedLibrary symbols.
                  (!symbol.flags.contains(.synthetic) || symbol.flags.contains(.importedLibrary)),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let signatureReceiver = signature.receiverType,
                  let (_, signatureReceiverSymbol) = resolveClassTypeSymbol(
                      sema.types.makeNonNullable(signatureReceiver),
                      sema: sema
                  ),
                  signatureReceiverSymbol.fqName == knownNames.kotlinCollectionsMutableCollectionFQName,
                  let parameterType = signature.parameterTypes.first,
                  let (_, parameterSymbol) = resolveClassTypeSymbol(
                      sema.types.makeNonNullable(parameterType),
                      sema: sema
                  )
            else {
                return false
            }
            return parameterSymbol.name == parameterID
        }
        guard let candidate else {
            return nil
        }
        guard let signature = sema.symbols.functionSignature(for: candidate) else {
            return nil
        }
        // The source declaration is generic in the receiver element type. The
        // regular resolver cannot unify that type parameter reliably when the
        // declaration came from imported stdlib metadata, so bind the exact
        // source overload after the nominal receiver/argument classification
        // above has selected it.
        let receiverElementType = collectionFallbackElementType(
            receiverID: receiverID,
            sema: sema,
            interner: interner
        )
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitutions = Dictionary(uniqueKeysWithValues: typeVarBySymbol.values.map {
            ($0, receiverElementType)
        })
        let returnType = driver.callChecker.bindCallAndResolveReturnType(
            exprID,
            chosen: candidate,
            resolved: ResolvedCall(
                chosenCallee: candidate,
                substitutedTypeArguments: substitutions,
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(exprID, type: finalType)
        return finalType
    }

    private func bindMutableSetPredicateSourceExtension(
        exprID: ExprID,
        memberName: InternedString,
        receiverID: ExprID,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        guard args.count == 1, args[0].label == nil else { return nil }

        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        guard memberName == knownNames.removeAll || memberName == knownNames.retainAll,
              let predicateExpr = ctx.ast.arena.expr(args[0].expr),
              predicateExpr.isLambdaOrCallableRef
        else {
            return nil
        }

        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        guard receiverClassifier.classify(receiverID: receiverID).isMutableSetReceiver else {
            return nil
        }

        let sourceFQName = knownNames.kotlinCollectionsPackage + [memberName]
        let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let signatureReceiver = signature.receiverType,
                  let (_, receiverSymbol) = resolveClassTypeSymbol(
                      sema.types.makeNonNullable(signatureReceiver),
                      sema: sema
                  ),
                  receiverSymbol.fqName == knownNames.kotlinCollectionsMutableIterableFQName,
                  case let .functionType(predicateType) = sema.types.kind(of:
                      sema.types.makeNonNullable(signature.parameterTypes[0])
                  )
            else {
                return false
            }
            return predicateType.params.count == 1
        }
        guard let chosenCallee else { return nil }

        let receiverElementType = collectionFallbackElementType(
            receiverID: receiverID,
            sema: sema,
            interner: interner
        )
        let predicateType = sema.types.make(.functionType(FunctionType(
            params: [receiverElementType],
            returnType: sema.types.booleanType
        )))

        // Pair properties on a collection HOF lambda use the collection element
        // binding path. The selected MutableIterable extension is source-backed,
        // so remove the marker again after inference to keep its ordinary
        // function-value ABI at the call site.
        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: predicateType
        )
        sema.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: [receiverElementType],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(exprID, target: .symbol(chosenCallee))
        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)

        let resultType = sema.types.booleanType
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(exprID, type: finalType)
        return finalType
    }

    private func validateCollectionFallbackCallee(
        _ fallbackCallee: SymbolID,
        exprID: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverID: ExprID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let diagnosticRange = ctx.ast.arena.exprRange(exprID) ?? ctx.ast.arena.exprRange(receiverID)

        if let diagnosticRange,
           let projectionDiagnostic = makeProjectionViolationDiagnostic(
            candidates: [fallbackCallee],
            receiverType: receiverType,
            calleeName: calleeName,
            range: diagnosticRange,
            sema: sema,
            interner: interner
        ) {
            ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
            let invalidType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
            sema.bindings.bindExprType(exprID, type: invalidType)
            return invalidType
        }

        guard let signature = sema.symbols.functionSignature(for: fallbackCallee),
              signature.classTypeParameterCount > 0,
              let receiverClassType = resolveClassType(receiverType, sema: sema)
        else {
            return nil
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        let receiverTypeParamCount = min(
            signature.classTypeParameterCount,
            receiverClassType.args.count,
            signature.typeParameterSymbols.count
        )

        for index in 0 ..< receiverTypeParamCount {
            let concreteType: TypeID = switch receiverClassType.args[index] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let typeParamSymbol = signature.typeParameterSymbols[index]
            if let typeVar = typeVarBySymbol[typeParamSymbol] {
                substitution[typeVar] = concreteType
            }
        }

        for index in 0 ..< receiverTypeParamCount {
            let typeParamSymbol = signature.typeParameterSymbols[index]
            guard let typeVar = typeVarBySymbol[typeParamSymbol],
                  let substitutedType = substitution[typeVar]
            else {
                continue
            }

            let signatureUpperBounds: [TypeID] = if index < signature.typeParameterUpperBoundsList.count {
                signature.typeParameterUpperBoundsList[index]
            } else {
                []
            }
            let symbolUpperBounds = sema.symbols.typeParameterUpperBounds(for: typeParamSymbol)
            let upperBounds = signatureUpperBounds + symbolUpperBounds.filter { bound in
                !signatureUpperBounds.contains(bound)
            }

            for bound in upperBounds {
                let substitutedBound = sema.types.substituteTypeParameters(
                    in: bound,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                if !sema.types.isSubtype(substitutedType, substitutedBound) {
                    if let diagnosticRange {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: diagnosticRange
                        )
                    }
                    let invalidType = safeCall ? sema.types.makeNullable(sema.types.anyType) : sema.types.anyType
                    sema.bindings.bindExprType(exprID, type: invalidType)
                    return invalidType
                }
            }
        }

        return nil
    }

    private func buildCollectionFallbackParameterMapping(
        args: [CallArgument],
        fallbackCallee: SymbolID,
        sema: SemaModule
    ) -> [Int: Int] {
        // Build a parameter mapping so that user-provided arguments are correctly
        // assigned to the right parameter slots. Without this, normalizedCallArguments
        // treats all parameters with hasDefault=true as using their default values,
        // ignoring user-provided args entirely.
        guard !args.isEmpty else {
            return [:]
        }
        guard let signature = sema.symbols.functionSignature(for: fallbackCallee) else {
            return [:]
        }
        let paramCount = signature.parameterTypes.count
        // Build a name->index map from the parameter symbols.
        var paramNameToIndex: [InternedString: Int] = [:]
        for (paramIndex, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            if let paramSymbolInfo = sema.symbols.symbol(paramSymbol) {
                let paramName = paramSymbolInfo.name
                if paramName != .invalid {
                    paramNameToIndex[paramName] = paramIndex
                }
            }
        }
        var mapping: [Int: Int] = [:]
        var positionalParamIndex = 0
        for (argIndex, arg) in args.enumerated() {
            if let label = arg.label, let paramIndex = paramNameToIndex[label] {
                // Named argument: map to the named parameter
                mapping[argIndex] = paramIndex
            } else {
                // Positional argument: advance to next unoccupied parameter index
                // (skip any params that are already claimed by named args)
                while positionalParamIndex < paramCount
                    && mapping.values.contains(positionalParamIndex)
                {
                    positionalParamIndex += 1
                }
                if positionalParamIndex < paramCount {
                    mapping[argIndex] = positionalParamIndex
                    positionalParamIndex += 1
                }
            }
        }
        // A trailing lambda (e.g. `windowed(3) { ... }`) always binds to the
        // callee's LAST parameter, skipping over any defaulted parameters in
        // between (`step`/`partialWindows`) -- it does not advance only one
        // slot past the last explicit positional argument. Without this fix,
        // the last arg lands on the next positional slot (`step`) instead of
        // `transform`, and the lambda silently vanishes: normalizedCallArguments
        // sees no argument mapped to the real last parameter and fills it from
        // its (nonexistent) default, while the lambda's value is discarded.
        if let lastArgIndex = args.indices.last,
           args[lastArgIndex].label == nil,
           paramCount > args.count,
           let lastParamType = signature.parameterTypes.last,
           case .functionType = sema.types.kind(of: sema.types.makeNonNullable(lastParamType))
        {
            mapping[lastArgIndex] = paramCount - 1
        }
        return mapping
    }

    private func resolveCollectionFallbackCallee(
        memberName: InternedString,
        receiverID: ExprID,
        argExprs: [ExprID] = [],
        argLabels: [InternedString?] = [],
        argCount: Int,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        // MutableMap contributes both the delegated `getValue` accessor and
        // the read-only Map `getValue(key)` extension. Resolve the latter
        // before the collection fallback's owner walk can select the delegate
        // accessor by short name.
        if memberName == knownNames.getValue,
           argCount == 1,
           receiverClassifier.isMutableMapType(receiverType)
        {
            let mapGetValueFQName = knownNames.kotlinCollectionsPackage + [memberName]
            if let chosen = sema.symbols.lookupAll(fqName: mapGetValueFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      (!symbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let receiverInfo = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return receiverInfo.fqName == knownNames.kotlinCollectionsMapFQName
            }) {
                return chosen
            }
        }
        // MutableMap.putAll(Map) is a member surface; the Iterable/Sequence/
        // Array overloads are source-backed extensions. Keep the member path
        // for Map arguments and choose the exact source parameter otherwise.
        if memberName == knownNames.putAll,
           argCount == 1,
           receiverClassifier.isMutableMapType(receiverType),
           let firstArgExpr = argExprs.first,
           let firstArgType = sema.bindings.exprTypes[firstArgExpr],
           !receiverClassifier.isMapLikeCollectionType(firstArgType)
        {
            let isArrayArgument = receiverClassifier.isArrayLikeReceiver(receiverID: firstArgExpr)
            let isSequenceArgument = receiverClassifier.isSequenceLikeType(firstArgType)
            if let chosen = sema.symbols.lookupAll(fqName: knownNames.kotlinCollectionsPackage + [memberName]).first(where: { candidate in
                   guard let symbol = sema.symbols.symbol(candidate),
                         symbol.kind == .function,
                         (!symbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate)),
                         let signature = sema.symbols.functionSignature(for: candidate),
                         signature.parameterTypes.count == 1,
                         let receiver = signature.receiverType,
                         let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                         let receiverInfo = sema.symbols.symbol(receiverSymbol),
                         let parameterSymbol = driver.helpers.nominalSymbol(
                             of: signature.parameterTypes[0], types: sema.types
                         ),
                         let parameterInfo = sema.symbols.symbol(parameterSymbol)
                   else {
                       return false
                   }
                   guard receiverInfo.fqName == knownNames.kotlinCollectionsMutableMapFQName else {
                       return false
                   }
                   if isArrayArgument {
                       return parameterInfo.fqName == knownNames.kotlinArrayFQName
                   }
                   if isSequenceArgument {
                       return parameterInfo.fqName == knownNames.kotlinSequenceFQName
                   }
                   return parameterInfo.fqName == knownNames.kotlinCollectionsIterableFQName
               })
            {
                return chosen
            }
        }
        let roots = driver.helpers.allNominalSymbols(
            of: sema.types.makeNonNullable(receiverType),
            types: sema.types,
            symbols: sema.symbols
        )
        guard !roots.isEmpty else {
            return nil
        }
        var queue: [SymbolID] = roots
        var queueHead = 0
        var visited: Set<SymbolID> = []
        while queueHead < queue.count {
            let owner = queue[queueHead]
            queueHead += 1
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [memberName]
            var allCandidates = sema.symbols.lookupAll(fqName: memberFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sema.symbols.functionSignature(for: candidate) != nil
                else {
                    return false
                }
                return true
            }
            for candidate in sema.symbols.lookupByShortName(memberName) {
                guard !allCandidates.contains(candidate),
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sema.symbols.functionSignature(for: candidate) != nil
                else {
                    continue
                }
                allCandidates.append(candidate)
            }
            // Named arguments can only bind to parameters a candidate actually
            // declares. Without this filter the arity-based matching below can
            // pick an overload that has none of the labels — e.g.
            // `joinToString(prefix = "<", postfix = ">")` matched the 2-param
            // `joinToString(separator, prefix)` source overload and bound the
            // `postfix` value to `separator`.
            let usedLabels = argLabels.compactMap { $0 }
            if !usedLabels.isEmpty {
                let labelMatches = allCandidates.filter { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    let parameterNames = Set(signature.valueParameterSymbols.compactMap { parameterSymbol in
                        sema.symbols.symbol(parameterSymbol)?.name
                    })
                    return usedLabels.allSatisfy { parameterNames.contains($0) }
                }
                if !labelMatches.isEmpty {
                    allCandidates = labelMatches
                }
            }
            // KSP-1001: List.slice has both IntRange and Iterable<Int>
            // overloads. The collection fallback is intentionally arity-based
            // for most legacy members, but selecting the first slice overload
            // would route a List<Int> argument to the IntRange declaration.
            if memberName == knownNames.slice,
               argCount == 1,
               let firstArgExpr = argExprs.first
            {
                let isIntRangeArgument: Bool = if let firstArgType = sema.bindings.exprTypes[firstArgExpr] {
                    if let (_, argumentSymbol) = resolveClassTypeSymbol(
                        sema.types.makeNonNullable(firstArgType), sema: sema
                    ) {
                        argumentSymbol.name == knownNames.intRange
                    } else {
                        sema.bindings.isRangeExpr(firstArgExpr) && firstArgType == sema.types.intType
                    }
                } else {
                    sema.bindings.isRangeExpr(firstArgExpr)
                }
                let targetParameterID = isIntRangeArgument ? knownNames.intRange : knownNames.iterable
                if let sliceMatch = allCandidates.first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == 1,
                          let (_, parameterSymbol) = resolveClassTypeSymbol(
                              sema.types.makeNonNullable(signature.parameterTypes[0]), sema: sema
                          )
                    else {
                        return false
                    }
                    return parameterSymbol.name == targetParameterID
                }) {
                    return sliceMatch
                }
            }
            if memberName == knownNames.addAll,
               argCount == 1,
               let firstArgExpr = argExprs.first,
               receiverClassifier.isArrayLikeReceiver(receiverID: firstArgExpr),
               let arrayMatch = allCandidates.first(where: { candidate in
                   guard let signature = sema.symbols.functionSignature(for: candidate),
                         let parameterType = signature.parameterTypes.first
                   else {
                       return false
                   }
                   return receiverClassifier.isArrayLikeType(parameterType)
               })
            {
                return arrayMatch
            }
            if memberName == knownNames.addAll,
               argCount == 1,
               let firstArgExpr = argExprs.first,
               let firstArgType = sema.bindings.exprTypes[firstArgExpr],
               receiverClassifier.isSequenceLikeType(firstArgType),
               let sequenceMatch = allCandidates.first(where: { candidate in
                   guard let sig = sema.symbols.functionSignature(for: candidate),
                         sig.parameterTypes.count == 1,
                         let firstParamType = sig.parameterTypes.first
                   else {
                       return false
                   }
                   return receiverClassifier.isSequenceLikeType(firstParamType)
               })
            {
                return sequenceMatch
            }
            if memberName == knownNames.addAll,
               argCount == 1,
               let firstArgExpr = argExprs.first,
               receiverClassifier.isIterableLikeReceiver(receiverID: firstArgExpr),
               !receiverClassifier.isCollectionLikeType(sema.bindings.exprTypes[firstArgExpr] ?? sema.types.anyType),
               let iterableMatch = allCandidates.first(where: { candidate in
                   guard let signature = sema.symbols.functionSignature(for: candidate),
                         let parameterType = signature.parameterTypes.first
                   else {
                       return false
                   }
                   return receiverClassifier.isExactIterableType(parameterType)
               })
            {
                return iterableMatch
            }

        let lastArgIsFunctionLike: Bool = if let lastExpr = argExprs.last,
                                             let lastExprNode = ctx.ast.arena.expr(lastExpr) {
            lastExprNode.isLambdaOrCallableRef
        } else {
            false
        }
        func hasFunctionTypedLastParam(_ candidate: SymbolID) -> Bool {
            guard let sig = sema.symbols.functionSignature(for: candidate),
                  let lastParamType = sig.parameterTypes.last
            else {
                return false
            }
            switch sema.types.kind(of: sema.types.makeNonNullable(lastParamType)) {
            case .functionType:
                return true
            default:
                return false
            }
        }
        // A trailing lambda binds to the callee's LAST parameter regardless of how
        // many parameters before it are defaulted (Kotlin's trailing-lambda syntax
        // skips over defaulted middle parameters). Requiring an exact arg-count
        // match here made `windowed(3) { ... }` (2 provided args: size, transform)
        // fail to match the real 4-param `windowed(size, step = 1,
        // partialWindows = false, transform)` overload, falling through to the
        // "first candidate" arity fallback below -- which silently picked the
        // unrelated 3-param no-transform overload (declared first in
        // SequenceWindowChunk.kt) and dropped the transform lambda entirely.
        func canMatchViaTrailingLambda(_ candidate: SymbolID) -> Bool {
            guard let sig = sema.symbols.functionSignature(for: candidate),
                  argCount >= 1,
                  sig.parameterTypes.count >= argCount,
                  hasFunctionTypedLastParam(candidate)
            else {
                return false
            }
            let skippedIndices = (argCount - 1) ..< (sig.parameterTypes.count - 1)
            return skippedIndices.allSatisfy { index in
                sig.valueParameterHasDefaultValues.indices.contains(index)
                    && sig.valueParameterHasDefaultValues[index]
            }
        }
        if lastArgIsFunctionLike,
           let lambdaMatch = allCandidates.first(where: canMatchViaTrailingLambda) {
            return lambdaMatch
        }
        // When the call site has no trailing lambda, an overload whose last parameter
        // is a function type (e.g. a `joinToString(..., transform)` HOF overload) can
        // never be the intended target. Excluding those candidates here prevents the
        // arity-only matching below from misrouting a plain call — e.g.
        // `joinToString(prefix = "<", postfix = ">")` (2 args, no lambda) must resolve
        // to the 3-param `(separator, prefix, postfix)` overload, not to a same-arity
        // `(separator, transform)` HOF overload registered for a different call shape.
        let arityCandidates = lastArgIsFunctionLike
            ? allCandidates
            : allCandidates.filter { !hasFunctionTypedLastParam($0) }
        // Prefer the overload whose parameter count matches the call-site
        // argument count so that e.g. windowed(3, 2, true) resolves to the
        // 3-param overload (kk_list_windowed_partial) instead of the 2-param
        // one (kk_list_windowed).
        if let exactMatch = arityCandidates.first(where: { candidate in
            guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
            return sig.parameterTypes.count == argCount
        }) {
            return exactMatch
        }
        if let first = arityCandidates.first {
            return first
        }
        queue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }
}
