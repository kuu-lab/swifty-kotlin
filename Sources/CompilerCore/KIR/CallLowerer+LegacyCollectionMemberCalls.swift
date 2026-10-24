extension CallLowerer {

    func lowerLegacyReduceRightOrNullFallback(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        chosenBase64Callee: SymbolID?,
        loweredReceiverID: KIRExprID,
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // BUG-167: reduceRightOrNull's bundled Kotlin-source declaration
        // (ListAggregateHOF.kt) is scoped to `List<T>` specifically (its body
        // needs indexed access), so bindBundledListSourceFunction
        // (CallTypeChecker+MemberCallInferenceCollectionFlow.swift) only binds
        // a chosenCallee for genuine List receivers there — a concrete Set
        // receiver reaches KIR with chosenBase64Callee == nil, and (unlike an
        // Iterable-typed variable, which the useIterableRuntimeForCollectionFallback
        // branch below already covers) had no other fallback here, so it fell
        // all the way through to a bare-Kotlin-name "give up" call and
        // produced an unresolved `_reduceRightOrNull` link error.
        // kk_sequence_reduceRightOrNull already reads its receiver through
        // runtimeCollectionElements (List- and Set-compatible), so any
        // concrete collection Sema didn't already bind can use it directly.
        if args.count == 1,
           chosenBase64Callee == nil,
           calleeNameStr == "reduceRightOrNull"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            // isConcreteCollectionLikeType (via isCollectionLikeSymbol) also
            // matches Sequence receivers -- Sequence must be excluded here so
            // it keeps going through the dedicated
            // useSequenceRuntimeForCollectionFallback dispatch below (which
            // correctly picks kk_sequence_reduceRightOrNull), rather than
            // being misrouted to kk_sequence_reduceRightOrNull and panicking on
            // an "invalid list handle" (a Sequence handle is not a List
            // handle).
            if isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner),
               !isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                instructions.append(.call(
                    callee: interner.intern("kk_sequence_reduceRightOrNull"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: true
                ))
                return result
            }
        }
        return nil
    }

    func lowerLegacyCollectionIsNullOrEmptyCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        chosenCalleeForArgumentAdaptation: SymbolID?,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // String.isNullOrEmpty/isNullOrBlank are bundled Kotlin source (KSP-401).
        if args.isEmpty {
            let calleeStr = calleeNameStr
            // A source-backed Collection<T>?.isNullOrEmpty() declaration may
            // be selected once the Collection surface is bundled from Kotlin
            // source, but concrete collection receivers still need their
            // type-specific non-throwing isEmpty bridge here.
            let isSourceBackedCollectionIsNullOrEmpty: Bool = {
                guard calleeStr == "isNullOrEmpty",
                      let chosenCallee = chosenCalleeForArgumentAdaptation,
                      let symbol = sema.symbols.symbol(chosenCallee),
                      sema.symbols.isSourceBackedSymbol(chosenCallee),
                      symbol.fqName == [
                          interner.intern("kotlin"),
                          interner.intern("collections"),
                          calleeName,
                      ]
                else {
                    return false
                }
                // `kotlin.collections.isNullOrEmpty` is overloaded per receiver
                // (Collection, Map, ...); the bare package+name FQN above can't
                // tell those apart since extension receivers aren't part of it.
                // Map's own isNullOrEmpty is also source-backed and must keep
                // calling through its Kotlin declaration (which owns the
                // private __kk_map_is_empty helper), so only take the
                // runtime-bridge fast path when the chosen overload's own
                // receiver is actually Collection<T>.
                guard let signatureReceiverType = sema.symbols.functionSignature(for: chosenCallee)?.receiverType,
                      let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiverType, sema: sema)
                else {
                    return false
                }
                return receiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Collection"),
                ]
            }()
            if calleeStr == "isNullOrEmpty",
               (sema.bindings.callBindings[exprID] == nil || isSourceBackedCollectionIsNullOrEmpty)
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let runtimeCallee = collectionIsNullOrEmptyRuntimeCallee(
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                )
                {
                    instructions.append(.call(callee: runtimeCallee, arguments: [loweredReceiverID], result: result, canThrow: false))
                    return result
                }
            }
        }
        return nil
    }

    func lowerLegacySingleArgArrayMemberCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.count == 1 else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            let calleeStr = calleeNameStr
            if calleeStr == "get" {
                instructions.append(.call(
                    callee: interner.intern("kk_array_get"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false
                ))
                return result
            }

            let rawRuntimeCallee: String? = switch calleeStr {
            case "fill":
                "kk_array_fill"
            case "firstNotNullOf":
                "__kk_iterable_firstNotNullOf"
            case "firstNotNullOfOrNull":
                "__kk_iterable_firstNotNullOfOrNull"
            default:
                nil
            }
            if let runtimeCallee = rawRuntimeCallee {
                let canThrow = runtimeCallee == "__kk_iterable_firstNotNullOf"
                    || runtimeCallee == "__kk_iterable_firstNotNullOfOrNull"
                let thrownResult = canThrow
                    ? arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                    : nil
                let hofArgIDs: [KIRExprID]
                if (calleeStr == "firstNotNullOf" || calleeStr == "firstNotNullOfOrNull"),
                   normalizedArgIDs.count < 2
                {
                    let closureRawExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: closureRawExpr, value: .intLiteral(0)))
                    hofArgIDs = normalizedArgIDs + [closureRawExpr]
                } else {
                    hofArgIDs = normalizedArgIDs
                }
                instructions.append(.call(
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID] + hofArgIDs,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                return result
            }
        }
        return nil
    }

    func lowerLegacySingleArgListMemberCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        chosenBase64Callee: SymbolID?,
        loweredReceiverID: KIRExprID,
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.count == 1 else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            let isSourceBackedListCall: Bool = {
                guard let sourceCallee = chosenBase64Callee,
                      let symbol = sema.symbols.symbol(sourceCallee),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(sourceCallee)
                else {
                    return false
                }
                return true
            }()
            if !isSourceBackedListCall {
            let calleeStr = calleeNameStr
            let primitiveSelectorKind = collectionSelectorPrimitiveCompareKind(of: args.first?.expr, sema: sema)
            let runtimeCallee: String? = switch calleeStr {
            case "sortedBy":
                primitiveSelectorKind != nil ? "kk_list_sortedBy_primitive" : "kk_list_sortedBy"
            case "sortedByDescending":
                primitiveSelectorKind != nil ? "kk_list_sortedByDescending_primitive" : "kk_list_sortedByDescending"
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
            case "partition":
                "kk_list_partition"
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
                let canThrow = runtimeCallee == "kk_list_minBy"
                instructions.append(.call(callee: interner.intern(runtimeCallee), arguments: callArguments, result: result, canThrow: canThrow))
                return result
                }
            }
        }
        return nil
    }

    func lowerLegacyListWindowChunkCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
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
                    // `normalizedArgIDs[valueArgCount]` is the transform callable
                    // in both shapes (unexpanded lambda, or the fnPtr of an
                    // already-expanded `addCollectionHOFClosureArguments` pair).
                    let (fnPtrExpr, envPtrExpr) = splitErasedTransformBridgeArgument(
                        normalizedArgIDs[valueArgCount],
                        existingEnvPtrID: normalizedArgIDs.count > valueArgCount + 1
                            ? normalizedArgIDs[valueArgCount + 1]
                            : nil,
                        argExprID: args[valueArgCount].expr,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return [loweredReceiverID, sizeArg, stepArg, partialArg, fnPtrExpr, envPtrExpr]
                }

                switch calleeNameStr {
                case "chunked" where !hasHOFLambdaArg && normalizedArgIDs.count == 1:
                    return appendBridgeCall(
                        "__kk_list_chunked",
                        [loweredReceiverID, normalizedArgIDs[0]],
                        canThrow: true
                    )
                case "chunked" where hasHOFLambdaArg && normalizedArgIDs.count == 2:
                    let (fnPtrExpr, envPtrExpr) = splitErasedTransformBridgeArgument(
                        normalizedArgIDs[1],
                        argExprID: args[1].expr,
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
                    return appendBridgeCall(
                        "__kk_list_windowed",
                        [loweredReceiverID, sizeArg, stepArg, partialArg],
                        canThrow: true
                    )
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
                    let (fnPtrExpr, envPtrExpr) = splitErasedTransformBridgeArgument(
                        normalizedArgIDs[1],
                        argExprID: args[1].expr,
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
                    let (fnPtrExpr, envPtrExpr) = splitErasedTransformBridgeArgument(
                        normalizedArgIDs[0],
                        argExprID: args[0].expr,
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
        return nil
    }

    func lowerLegacyZeroArgArrayConversionCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        isSourceBackedArrayToListCall: Bool,
        isSourceBackedArrayToMutableListCall: Bool,
        isSourceBackedArrayConversionCall: Bool,
        isSourceBackedArrayCopyCall: Bool,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            let runtimeCallee: String? = switch calleeNameStr {
            case "toList":
                isSourceBackedArrayToListCall ? nil : "__kk_array_toList"
            case "toMutableList":
                isSourceBackedArrayToMutableListCall ? nil : "kk_array_toMutableList"
            case "toTypedArray":
                isSourceBackedArrayConversionCall ? nil : "__kk_array_copyOf"
            case "copyOf":
                isSourceBackedArrayCopyCall ? nil : "__kk_array_copyOf"
            case "concatToString":
                "kk_chararray_concatToString"
            default:
                nil
            }
            if let runtimeCallee {
                instructions.append(.call(callee: interner.intern(runtimeCallee), arguments: [loweredReceiverID], result: result, canThrow: false))
                return result
            }
        }
        return nil
    }

}
