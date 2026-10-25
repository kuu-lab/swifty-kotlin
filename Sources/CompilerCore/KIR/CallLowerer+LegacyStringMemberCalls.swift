extension CallLowerer {

    func lowerLegacyStringLengthCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.isEmpty, calleeNameStr == "length" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    callee: interner.intern("__kk_string_struct_get_length"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false
                ))
                return result
            }
            // KSP-724: `CharSequence.length` is resolved through the bundled
            // `kotlin.CharSequence` interface property, so the `kk_char_sequence_length`
            // name-string fallback is no longer needed here.
        }
        return nil
    }

    func lowerLegacyZeroArgStringMemberCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let calleeStr = calleeNameStr
                if calleeStr == "lowercase" {
                    instructions.append(.call(
                        callee: interner.intern("kk_string_lowercase_flat"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false
                    ))
                    return result
                }
                if calleeStr == "uppercase" {
                    instructions.append(.call(
                        callee: interner.intern("kk_string_uppercase_flat"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false
                    ))
                    return result
                }
                if calleeStr == "toRegex" {
                    instructions.append(.call(
                        callee: interner.intern("__kk_string_toRegex_flat"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false
                    ))
                    return result
                }
                if calleeStr == "first" || calleeStr == "last" || calleeStr == "single" {
                    let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
                    let kkName = calleeStr == "first" ? "__kk_string_first_flat"
                        : calleeStr == "last" ? "__kk_string_last_flat"
                        : "__kk_string_single_flat"
                    instructions.append(.call(
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID, thrownExpr],
                        result: result,
                        canThrow: true
                    ))
                    return result
                }
                if calleeStr == "firstOrNull" || calleeStr == "lastOrNull" || calleeStr == "singleOrNull" {
                    let kkName = calleeStr == "firstOrNull" ? "__kk_string_firstOrNull_flat"
                        : calleeStr == "lastOrNull" ? "__kk_string_lastOrNull_flat"
                        : "__kk_string_singleOrNull_flat"
                    instructions.append(.call(callee: interner.intern(kkName), arguments: [loweredReceiverID], result: result, canThrow: false))
                    return result
                }
            }
        }
        return nil
    }

    func lowerLegacySingleArgStringMemberCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = calleeNameStr
            let isCharSequenceTextHelper = calleeStr == "ifBlank"
                || calleeStr == "ifEmpty"
            let usesStringFlatABI = sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("CharSequence"),
                ]) else {
                    return false
                }
                let charSequenceType = sema.types.make(.classType(ClassType(
                    classSymbol: charSequenceSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                return sema.types.isSubtype(nonNullReceiverType, charSequenceType)
            }()
            if isCharSequenceReceiver,
               !usesStringFlatABI,
               isCharSequenceTextHelper
            {
                let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                    loweredArgIDs[0],
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                let runtimeCallee = calleeStr == "ifBlank"
                    ? "kk_charsequence_ifBlank"
                    : "kk_charsequence_ifEmpty"
                instructions.append(.call(
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID, fnPtrExpr, envPtrExpr],
                    result: result,
                    canThrow: true
                ))
                return result
            }
            if usesStringFlatABI {
                if calleeStr == "toRegex" {
                    let argType = sema.bindings.exprTypes[args[0].expr]
                    let isSetArg: Bool = {
                        guard let argType,
                              let (_, sym) = resolveClassTypeSymbol(argType, sema: sema)
                        else { return false }
                        let knownNames = KnownCompilerNames(interner: interner)
                        return knownNames.isSetLikeSymbol(sym)
                    }()
                    let rtName = isSetArg
                        ? "__kk_string_toRegex_with_options_flat"
                        : "__kk_string_toRegex_with_option_flat"
                    instructions.append(.call(
                        callee: interner.intern(rtName),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false
                    ))
                    return result
                }
                let flatStringHOFArguments: [KIRExprID]? = {
                    guard isCharSequenceTextHelper else { return nil }
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        loweredArgIDs[0],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return [loweredReceiverID, fnPtrExpr, envPtrExpr]
                }()
                let runtimeCall: (callee: String, arguments: [KIRExprID])? = switch calleeStr {
                case "split":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        nil
                    } else {
                        nil
                    }
                case "contains":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("__kk_string_contains_regex_flat", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        nil
                    }
                case "ifBlank":
                    flatStringHOFArguments.map { ("kk_string_ifBlank_flat", $0) }
                case "ifEmpty":
                    flatStringHOFArguments.map { ("kk_string_ifEmpty_flat", $0) }
                default:
                    nil
                }
                if let runtimeCall {
                    let stringHOFCanThrow = calleeStr == "ifBlank"
                        || calleeStr == "ifEmpty"
                    let stringHOFThrownResult: KIRExprID? = nil
                    instructions.append(.call(
                        callee: interner.intern(runtimeCall.callee),
                        arguments: runtimeCall.arguments,
                        result: result,
                        canThrow: stringHOFCanThrow,
                        thrownResult: stringHOFThrownResult
                    ))
                    return result
                }
            }
        }
        return nil
    }

    func lowerLegacyRegexMemberCall(
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
        guard args.count == 1 else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let isSourceBackedRegexCall = chosenBase64Callee.map {
            sema.symbols.isSourceBackedSymbol($0)
        } ?? false
        if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner),
           !isSourceBackedRegexCall
        {
            let calleeStr = calleeNameStr
            let usesStringFlatABI: Bool = {
                guard let argumentType = sema.bindings.exprTypes[args[0].expr] else {
                    return false
                }
                return sema.types.isSubtype(
                    sema.types.makeNonNullable(argumentType),
                    sema.types.stringType
                )
            }()
            let runtimeCallee: String? = switch calleeStr {
            case "find":
                usesStringFlatABI ? "__kk_regex_find_flat" : nil
            case "findAll":
                usesStringFlatABI ? "__kk_regex_findAll_flat" : nil
            default:
                nil
            }
            if let runtimeCallee {
                instructions.append(.call(
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: false
                ))
                return result
            }
        }
        return nil
    }

    func lowerLegacyStringFormatCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if calleeNameStr == "format",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "__kk_string_format_flat"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                func boxedFormatArgument(_ argExpr: ExprID, loweredArgID: KIRExprID) -> KIRExprID {
                    let argType = sema.bindings.exprTypes[argExpr] ?? sema.types.anyType
                    let nonNullArgType = sema.types.makeNonNullable(argType)
                    return boxValueForAnySlot(
                        loweredArgID,
                        sourceType: nonNullArgType,
                        types: sema.types,
                        symbols: sema.symbols,
                        interner: interner,
                        arena: arena,
                        resultType: sema.types.nullableAnyType,
                        sema: sema,
                        into: &instructions
                    )
                }

                let boxedArgIDs = zip(args, loweredArgIDs).map { arg, loweredArgID in
                    boxedFormatArgument(arg.expr, loweredArgID: loweredArgID)
                }

                let packedArgs: KIRExprID
                if boxedArgIDs.count == 1, args.first?.isSpread == true {
                    packedArgs = boxedArgIDs[0]
                } else {
                    packedArgs = driver.callSupportLowerer.packVarargArguments(
                        argIndices: Array(boxedArgIDs.indices),
                        providedArguments: boxedArgIDs,
                        spreadFlags: args.map(\.isSpread),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.nullableAnyType,
                        types: sema.types,
                        symbols: sema.symbols,
                        sema: sema,
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    callee: interner.intern("__kk_string_format_flat"),
                    arguments: [loweredReceiverID, packedArgs],
                    result: result,
                    canThrow: true
                ))
                return result
            }
        }
        return nil
    }

}
