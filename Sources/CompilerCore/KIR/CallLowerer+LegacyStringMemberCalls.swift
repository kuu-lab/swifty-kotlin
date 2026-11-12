extension CallLowerer {

    func lowerLegacyStringLengthCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.isEmpty, calleeName == interner.intern("length") {
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
        calleeName: InternedString,
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
                let knownNames = KnownCompilerNames(interner: interner)
                let firstName = knownNames.first
                let lastName = knownNames.last
                let singleName = interner.intern("single")
                if calleeName == firstName || calleeName == lastName || calleeName == singleName {
                    let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
                    let kkName = calleeName == firstName ? "__kk_string_first_flat"
                        : calleeName == lastName ? "__kk_string_last_flat"
                        : "__kk_string_single_flat"
                    instructions.append(.call(
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID, thrownExpr],
                        result: result,
                        canThrow: true
                    ))
                    return result
                }
            }
        }
        return nil
    }

    func lowerLegacySingleArgStringMemberCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
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
            let knownNames = KnownCompilerNames(interner: interner)
            let ifBlankName = interner.intern("ifBlank")
            let ifEmptyName = interner.intern("ifEmpty")
            let toRegexName = interner.intern("toRegex")
            let isCharSequenceTextHelper = calleeName == ifBlankName
                || calleeName == ifEmptyName
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
                let runtimeCallee = calleeName == ifBlankName
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
                if calleeName == toRegexName {
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
                let runtimeCall: (callee: String, arguments: [KIRExprID])? = switch calleeName {
                case knownNames.contains:
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("__kk_string_contains_regex_flat", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        nil
                    }
                case ifBlankName:
                    flatStringHOFArguments.map { ("kk_string_ifBlank_flat", $0) }
                case ifEmptyName:
                    flatStringHOFArguments.map { ("kk_string_ifEmpty_flat", $0) }
                default:
                    nil
                }
                if let runtimeCall {
                    let stringHOFCanThrow = calleeName == ifBlankName
                        || calleeName == ifEmptyName
                    instructions.append(.call(
                        callee: interner.intern(runtimeCall.callee),
                        arguments: runtimeCall.arguments,
                        result: result,
                        canThrow: stringHOFCanThrow
                    ))
                    return result
                }
            }
        }
        return nil
    }

    func lowerLegacyRegexMemberCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
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
            let usesStringFlatABI: Bool = {
                guard let argumentType = sema.bindings.exprTypes[args[0].expr] else {
                    return false
                }
                return sema.types.isSubtype(
                    sema.types.makeNonNullable(argumentType),
                    sema.types.stringType
                )
            }()
            let findName = interner.intern("find")
            let findAllName = interner.intern("findAll")
            let runtimeCallee: String? = switch calleeName {
            case findName:
                usesStringFlatABI ? "__kk_regex_find_flat" : nil
            case findAllName:
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
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if calleeName == interner.intern("format"),
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
