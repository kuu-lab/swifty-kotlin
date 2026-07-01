// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallLowerer {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func tryLowerStringStdlibMemberCall(
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
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.isEmpty, interner.resolve(calleeName) == "length" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_length"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Char.digitToInt() / Char.digitToIntOrNull() (STDLIB-083)
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == sema.types.charType {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "digitToInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToInt"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "digitToIntOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToIntOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                // Char.code → identity (Char is stored as its Int code point) (STDLIB-305)
                if calleeStr == "code" {
                    instructions.append(.copy(from: loweredReceiverID, to: result))
                    return result
                }
            }
        }

        // STDLIB-003-ABI-001: Char.digitToInt(radix: Int) / Char.digitToIntOrNull(radix: Int) — 1-arg overloads
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == sema.types.charType {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "digitToInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToInt_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "digitToIntOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToIntOrNull_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Int.digitToChar() / Int.digitToChar(radix: Int) (DOCPARITY-CHAR-005)
        if args.count <= 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == sema.types.intType, interner.resolve(calleeName) == "digitToChar" {
                if args.isEmpty {
                    let radixExpr = arena.appendExpr(.intLiteral(10), type: sema.types.intType)
                    instructions.append(.constValue(result: radixExpr, value: .intLiteral(10)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToChar_radix"),
                        arguments: [loweredReceiverID, radixExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                } else {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_char_digitToChar_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                }
                return result
            }
        }

        // filterIsInstance<R>() — encode type token from result type (STDLIB-114 / STDLIB-SEQ-FN-026)
        if args.isEmpty, interner.resolve(calleeName) == "filterIsInstance" {
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            // Extract element type from List<R> or Sequence<R>.
            let elementType: TypeID = if case let .classType(classType) = sema.types.kind(of: nonNullResultType),
                                         let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let encodedToken = RuntimeTypeCheckToken.encode(type: elementType, sema: sema, interner: interner)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let runtimeCallee = isSequenceLikeType(sema.types.makeNonNullable(receiverType), sema: sema, interner: interner)
                ? "kk_sequence_filterIsInstance"
                : "kk_list_filterIsInstance"
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeCallee),
                arguments: [loweredReceiverID, tokenExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // filterIsInstanceTo<R>(destination) — encode type token from result type (STDLIB-021)
        if args.count == 1, interner.resolve(calleeName) == "filterIsInstanceTo" {
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            // Extract element type from MutableCollection<R>
            let elementType: TypeID = if case let .classType(classType) = sema.types.kind(of: nonNullResultType),
                                         let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let encodedToken = RuntimeTypeCheckToken.encode(type: elementType, sema: sema, interner: interner)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            let nonNullReceiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType)
            let runtimeCallee = if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                interner.intern("kk_sequence_filterIsInstanceTo")
            } else {
                interner.intern("kk_list_filterIsInstanceTo")
            }
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [loweredReceiverID, loweredArgIDs[0], tokenExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // String stdlib: nullable-receiver 0-arg methods (NULL-002)
        // isNullOrEmpty/isNullOrBlank pass the raw (potentially null) receiver pointer to C runtime.
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if sema.bindings.callBindings[exprID] == nil,
               calleeStr == "isNullOrEmpty" || calleeStr == "isNullOrBlank"
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if calleeStr == "isNullOrEmpty",
                   let runtimeCallee = collectionIsNullOrEmptyRuntimeCallee(
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                   )
                {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    let runtimeCallee = calleeStr == "isNullOrEmpty"
                        ? "kk_string_isNullOrEmpty"
                        : "kk_string_isNullOrBlank"
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
            // STDLIB-532/533/534, STDLIB-SEQ-011: orEmpty() on nullable receivers
            if sema.bindings.callBindings[exprID] == nil, calleeStr == "orEmpty" {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_list_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_sequence_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if isMapLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_map_orEmpty"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }
        // String stdlib: 0-arg methods (STDLIB-006)
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let calleeStr = interner.resolve(calleeName)

                if calleeStr == "toInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toInt"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toIntOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toIntOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toDouble" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toDouble"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toDoubleOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toDoubleOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toFloatOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toFloatOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toBigInteger" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toBigInteger"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toBigIntegerOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toBigIntegerOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toBigDecimal" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toBigDecimal"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toBigDecimalOrNull" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toBigDecimalOrNull"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toList" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toList"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toMutableList" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toMutableList"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toSortedSet" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toSortedSet"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asIterable" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asIterable"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toCharArray" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toCharArray"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toRegex" {
                    if args.count == 1 {
                        let argID = loweredArgIDs[0]
                        let argType = sema.bindings.exprTypes[args[0].expr]
                        let knownNames = KnownCompilerNames(interner: interner)
                        let isSetArg: Bool = {
                            guard let argType,
                                  case let .classType(ct) = sema.types.kind(of: sema.types.makeNonNullable(argType)),
                                  let sym = sema.symbols.symbol(ct.classSymbol)
                            else { return false }
                            return knownNames.isSetLikeSymbol(sym)
                        }()
                        let rtName = isSetArg ? "kk_string_toRegex_with_options" : "kk_string_toRegex_with_option"
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern(rtName),
                            arguments: [loweredReceiverID, argID],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        return result
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toRegex"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "lines" || calleeStr == "lineSequence" {
                    let rtName = calleeStr == "lineSequence"
                        ? "kk_string_lineSequence" : "kk_string_lines"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(rtName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "first" || calleeStr == "last" || calleeStr == "single" {
                    let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
                    let kkName = calleeStr == "first" ? "kk_string_first"
                        : calleeStr == "last" ? "kk_string_last"
                        : "kk_string_single"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID, thrownExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "firstOrNull" || calleeStr == "lastOrNull" || calleeStr == "singleOrNull" {
                    let kkName = calleeStr == "firstOrNull" ? "kk_string_firstOrNull"
                        : calleeStr == "lastOrNull" ? "kk_string_lastOrNull"
                        : "kk_string_singleOrNull"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeName == interner.intern("zipWithNext") {
                    // String.zipWithNext overload dispatch: no-arg → kk_string_zipWithNext,
                    // transform → kk_string_zipWithNextTransform.
                    let runtimeCallee = args.isEmpty ? "kk_string_zipWithNext" : "kk_string_zipWithNextTransform"
                    let callArguments = args.isEmpty ? [loweredReceiverID] : [loweredReceiverID] + normalizedArgIDs
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: !args.isEmpty,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeName == interner.intern("zip"), args.count >= 1 {
                    // String.zip overload dispatch: 1-arg (other) → kk_string_zip,
                    // 2-arg (other + transform) → kk_string_zipTransform.
                    let hasTransform = args.count >= 2
                    let runtimeCallee = hasTransform ? "kk_string_zipTransform" : "kk_string_zip"
                    let callArguments = [loweredReceiverID] + normalizedArgIDs
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: hasTransform,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asSequence" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asSequence"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "asIterable" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_asIterable"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "withIndex" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_withIndex"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "intern" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_intern"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "trim" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_trim"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "trimStart" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_trimStart"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "trimEnd" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_trimEnd"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: 1-arg methods (STDLIB-006)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            let isCharSequenceTextHelper = calleeStr == "ifBlank"
                || calleeStr == "ifEmpty"
                || calleeStr == "chunkedSequence"
                || calleeStr == "firstNotNullOf"
                || calleeStr == "firstNotNullOfOrNull"
                || calleeStr == "reduce"
                || calleeStr == "reduceOrNull"
                || calleeStr == "reduceRightIndexed"
                || calleeStr == "reduceRightIndexedOrNull"
                || calleeStr == "reduceRightOrNull"
                || calleeStr == "sumBy"
                || calleeStr == "sumByDouble"
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
                || (isCharSequenceTextHelper && isCharSequenceReceiver)
            {
                if calleeStr == "firstNotNullOf"
                    || calleeStr == "firstNotNullOfOrNull"
                    || calleeStr == "reduceOrNull"
                    || calleeStr == "reduceRightIndexed"
                    || calleeStr == "reduceRightIndexedOrNull"
                    || calleeStr == "reduceRightOrNull"
                    || calleeStr == "sumBy"
                    || calleeStr == "sumByDouble"
                    || calleeStr == "onEachIndexed"
                {
                    let originalCallBinding = sema.bindings.callBindings[exprID]
                    let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                        chosen
                    } else {
                        nil
                    }
                    let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                        providedArguments: loweredArgIDs,
                        callBinding: originalCallBinding,
                        chosenCallee: originalChosen,
                        spreadFlags: args.map(\.isSpread),
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    ).arguments
                    let transformArg = normalizedOriginalArgs.first ?? loweredArgIDs[0]
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        transformArg,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    let runtimeCallee = switch calleeStr {
                    case "firstNotNullOf": "kk_string_firstNotNullOf"
                    case "firstNotNullOfOrNull": "kk_string_firstNotNullOfOrNull"
                    case "reduceOrNull": "kk_string_reduceOrNull"
                    case "reduceRightIndexed": "kk_string_reduceRightIndexed"
                    case "reduceRightIndexedOrNull": "kk_string_reduceRightIndexedOrNull"
                    case "sumBy": "kk_string_sumBy"
                    case "sumByDouble": "kk_string_sumByDouble"
                    case "onEachIndexed": "kk_string_onEachIndexed"
                    default: "kk_string_reduceRightOrNull"
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID, fnPtrExpr, envPtrExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toInt" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_toInt_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "substring" {
                    let hasEndExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: hasEndExpr, value: .intLiteral(0)))
                    let endExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: endExpr, value: .intLiteral(0)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_substring"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], endExpr, hasEndExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                let stringGetThrownExpr: KIRExprID?
                if calleeStr == "get" {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    stringGetThrownExpr = zeroExpr
                } else {
                    stringGetThrownExpr = nil
                }

                // STDLIB-TEXT-FN-020: CharSequence.indexOf(Char) — 1-arg overload routes to the dedicated Char runtime entry.
                if calleeStr == "indexOf",
                   sema.types.isSubtype(
                       sema.types.makeNonNullable(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType),
                       sema.types.charType
                   )
                {
                    let zeroIndexExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroIndexExpr, value: .intLiteral(0)))
                    let falseExpr = arena.appendExpr(.intLiteral(0), type: sema.types.booleanType)
                    instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_indexOf_char"),
                        arguments: [loweredReceiverID, loweredArgIDs[0], zeroIndexExpr, falseExpr],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let runtimeCall: (callee: String, arguments: [KIRExprID])? = switch calleeStr {
                case "split":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("kk_string_split_regex", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_split", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "startsWith":
                    ("kk_string_startsWith", [loweredReceiverID, loweredArgIDs[0]])
                case "endsWith":
                    ("kk_string_endsWith", [loweredReceiverID, loweredArgIDs[0]])
                case "contains":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("kk_string_contains_regex", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        ("kk_string_contains_str", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "indexOf":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_indexOf_from", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_indexOf", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "lastIndexOf":
                    ("kk_string_lastIndexOf", [loweredReceiverID, loweredArgIDs[0]])
                case "get":
                    ("kk_string_get", [loweredReceiverID, loweredArgIDs[0], stringGetThrownExpr!])
                case "compareTo":
                    ("kk_string_compareTo_member", [loweredReceiverID, loweredArgIDs[0]])
                case "matches":
                    ("kk_string_matches_regex", [loweredReceiverID, loweredArgIDs[0]])

                case "mapIndexed":
                    ("kk_string_mapIndexed", [loweredReceiverID] + normalizedArgIDs)
                case "mapNotNull":
                    ("kk_string_mapNotNull", [loweredReceiverID] + normalizedArgIDs)
                case "filterIndexed":
                    ("kk_string_filterIndexed", [loweredReceiverID] + normalizedArgIDs)
                case "filterNot":
                    ("kk_string_filterNot", [loweredReceiverID] + normalizedArgIDs)
                case "indexOfFirst":
                    ("kk_string_indexOfFirst", [loweredReceiverID] + normalizedArgIDs)
                case "indexOfLast":
                    ("kk_string_indexOfLast", [loweredReceiverID] + normalizedArgIDs)
                case "takeWhile":
                    ("kk_string_takeWhile", [loweredReceiverID] + normalizedArgIDs)
                case "takeLastWhile":
                    ("kk_string_takeLastWhile", [loweredReceiverID] + normalizedArgIDs)
                case "dropWhile":
                    ("kk_string_dropWhile", [loweredReceiverID] + normalizedArgIDs)
                case "onEach":
                    ("kk_string_onEach", [loweredReceiverID] + normalizedArgIDs)
                case "splitToSequence":
                    ("kk_string_splitToSequence", [loweredReceiverID] + normalizedArgIDs)
                case "find":
                    ("kk_string_find", [loweredReceiverID] + normalizedArgIDs)
                case "findLast":
                    ("kk_string_findLast", [loweredReceiverID] + normalizedArgIDs)
                case "reduce":
                    ("kk_string_reduce", [loweredReceiverID] + normalizedArgIDs)
                case "singleOrNull":
                    ("kk_string_singleOrNull_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "partition":
                    ("kk_string_partition", [loweredReceiverID] + normalizedArgIDs)
                case "ifBlank":
                    ("kk_string_ifBlank", [loweredReceiverID] + normalizedArgIDs)
                case "ifEmpty":
                    ("kk_string_ifEmpty", [loweredReceiverID] + normalizedArgIDs)
                case "chunked":
                    ("kk_string_chunked", [loweredReceiverID, loweredArgIDs[0]])
                case "take":
                    ("kk_string_take", [loweredReceiverID, loweredArgIDs[0]])
                case "drop":
                    ("kk_string_drop", [loweredReceiverID, loweredArgIDs[0]])
                case "takeLast":
                    ("kk_string_takeLast", [loweredReceiverID, loweredArgIDs[0]])
                case "dropLast":
                    ("kk_string_dropLast", [loweredReceiverID, loweredArgIDs[0]])
                case "chunkedSequence":
                    ("kk_string_chunked_sequence", [loweredReceiverID, loweredArgIDs[0]])
                case "toByteArray":
                    if loweredArgIDs.count == 1 {
                        // toByteArray(charset) — Sema types this as List<Int>, so use the ListBox-returning function.
                        ("kk_string_toByteArray_charset", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        // toByteArray(startIndex, endIndex) — shares the ArrayBox-returning range function with encodeToByteArray.
                        ("kk_string_encodeToByteArray_range", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    }
                case "commonPrefixWith":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_commonPrefixWith_ignoreCase", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_commonPrefixWith", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "commonSuffixWith":
                    if loweredArgIDs.count >= 2 {
                        ("kk_string_commonSuffixWith_ignoreCase", [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]])
                    } else {
                        ("kk_string_commonSuffixWith", [loweredReceiverID, loweredArgIDs[0]])
                    }
                case "removePrefix":
                    ("kk_string_removePrefix", [loweredReceiverID, loweredArgIDs[0]])
                case "removeSuffix":
                    ("kk_string_removeSuffix", [loweredReceiverID, loweredArgIDs[0]])
                case "removeSurrounding":
                    ("kk_string_removeSurrounding", [loweredReceiverID, loweredArgIDs[0]])
                case "trim":
                    ("kk_string_trim_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "trimStart":
                    ("kk_string_trimStart_predicate", [loweredReceiverID] + normalizedArgIDs)
                case "trimEnd":
                    ("kk_string_trimEnd_predicate", [loweredReceiverID] + normalizedArgIDs)
                default:
                    nil
                }
                if let runtimeCall {
                    let stringHOFCanThrow = calleeStr == "indexOfFirst"
                        || calleeStr == "indexOfLast"
                        || calleeStr == "reduce"
                        || calleeStr == "partition"
                        || calleeStr == "ifBlank"
                        || calleeStr == "ifEmpty"
                        || calleeStr == "trim"
                        || calleeStr == "trimStart"
                        || calleeStr == "trimEnd"
                        || calleeStr == "take"
                        || calleeStr == "drop"
                        || calleeStr == "takeLast"
                        || calleeStr == "dropLast"
                    // Only `partition` captures the thrown result into a register so the
                    // caller can inspect it.  All other HOFs propagate exceptions through
                    // the standard thrown-channel codegen path (thrownResult == nil),
                    // which emits an early return when the channel is non-zero.  Setting
                    // thrownResult to non-nil for those HOFs would silently swallow the
                    // exception instead of propagating it.
                    let stringHOFThrownResult: KIRExprID? = calleeStr == "partition"
                        ? arena.appendTemporary(type: sema.types.nullableAnyType
                        )
                        : nil
                    instructions.append(.call(
                        symbol: nil,
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

        // STDLIB-TEXT-EDGE-001: split(delimiter, limit) — 2-arg overload
        if args.count == 2, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.intType)
            {
                let falseExpr = arena.appendExpr(.intLiteral(0), type: sema.types.booleanType)
                instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], falseExpr, loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, ignoreCase) — 2-arg overload
        if args.count == 2, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.booleanType)
            {
                // limit = 0 means "no limit" for Kotlin's split overload.
                let zeroLimitExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroLimitExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], zeroLimitExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-EDGE-001: split(delimiter, ignoreCase, limit) — 3-arg overload
        if args.count == 3, interner.resolve(calleeName) == "split" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let secondArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[1].expr] ?? sema.types.anyType
            )
            let thirdArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[2].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(firstArgType, sema.types.stringType),
               sema.types.isSubtype(secondArgType, sema.types.booleanType),
               sema.types.isSubtype(thirdArgType, sema.types.intType)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split_limit"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: 2-arg overloads (STDLIB-009, STDLIB-549)
        // KNOWN LIMITATION: The dispatch below matches purely on function name + receiver
        // type (String). User-defined extension functions with the same name (e.g.
        // `fun String.windowed(...)`) will be incorrectly intercepted. A future fix
        // should check the resolved symbol's origin (synthetic vs user-defined) before
        // rewriting to the runtime call.
        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver,
               calleeStr == "chunkedSequence",
               normalizedArgIDs.count >= 3
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_chunked_sequence_transform"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "subSequence"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_subSequence"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "indexOf",
               sema.types.isSubtype(firstArgType, sema.types.stringType)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_indexOf_from"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // STDLIB-TEXT-FN-020: CharSequence.indexOf(Char, startIndex) — 2-arg overload routes to kk_string_indexOf_char.
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver,
               calleeStr == "indexOf",
               sema.types.isSubtype(firstArgType, sema.types.charType)
            {
                let falseExpr = arena.appendExpr(.intLiteral(0), type: sema.types.booleanType)
                instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_indexOf_char"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], falseExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver,
               calleeStr == "chunkedSequence"
            {
                let lambdaArgIndex = args.indices.first { index in
                    ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
                        || sema.bindings.isCollectionHOFLambdaExpr(args[index].expr)
                }
                let sizeArgIndex = args.indices.first { index in
                    if let lambdaArgIndex {
                        return index != lambdaArgIndex
                    }
                    return false
                }
                let callArguments: [KIRExprID]
                let originalCallBinding = sema.bindings.callBindings[exprID]
                let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                    chosen
                } else {
                    nil
                }
                let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredArgIDs,
                    callBinding: originalCallBinding,
                    chosenCallee: originalChosen,
                    spreadFlags: args.map(\.isSpread),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ).arguments
                if normalizedOriginalArgs.count == 2 {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedOriginalArgs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [loweredReceiverID, normalizedOriginalArgs[0], fnPtrExpr, envPtrExpr]
                } else if let lambdaArgIndex,
                          let sizeArgIndex,
                          lambdaArgIndex < loweredArgIDs.count,
                          sizeArgIndex < loweredArgIDs.count
                {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        loweredArgIDs[lambdaArgIndex],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [loweredReceiverID, loweredArgIDs[sizeArgIndex], fnPtrExpr, envPtrExpr]
                } else {
                    callArguments = [loweredReceiverID] + normalizedArgIDs
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_chunked_sequence_transform"),
                    arguments: callArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "compareTo"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_compareToIgnoreCase"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               calleeStr == "substring"
            {
                let hasEndExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
                instructions.append(.constValue(result: hasEndExpr, value: .intLiteral(1)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_substring"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], hasEndExpr],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: 2-arg removeSurrounding(prefix, suffix) (STDLIB-TEXT-EDGE-010 / STDLIB-185)
        if args.count == 2, interner.resolve(calleeName) == "removeSurrounding" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeSurrounding_pair"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 3 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver,
               calleeStr == "windowedSequence"
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_windowedSequence_partial"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.count == 4 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) || isCharSequenceReceiver,
               calleeStr == "windowedSequence"
            {
                let lambdaArgIndex = args.indices.first { index in
                    ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
                        || sema.bindings.isCollectionHOFLambdaExpr(args[index].expr)
                }
                let originalCallBinding = sema.bindings.callBindings[exprID]
                let originalChosen: SymbolID? = if let chosen = originalCallBinding?.chosenCallee, chosen != .invalid {
                    chosen
                } else {
                    nil
                }
                let normalizedOriginalArgs = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredArgIDs,
                    callBinding: originalCallBinding,
                    chosenCallee: originalChosen,
                    spreadFlags: args.map(\.isSpread),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ).arguments
                let callArguments: [KIRExprID]?
                if normalizedOriginalArgs.count == 4 {
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedOriginalArgs[3],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    callArguments = [
                        loweredReceiverID,
                        normalizedOriginalArgs[0],
                        normalizedOriginalArgs[1],
                        normalizedOriginalArgs[2],
                        fnPtrExpr,
                        envPtrExpr,
                    ]
                } else if let lambdaArgIndex,
                          lambdaArgIndex < loweredArgIDs.count
                {
                    let scalarArgIDs = args.indices
                        .filter { $0 != lambdaArgIndex }
                        .compactMap { index -> KIRExprID? in
                            guard index < loweredArgIDs.count else { return nil }
                            return loweredArgIDs[index]
                        }
                    if scalarArgIDs.count == 3 {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            loweredArgIDs[lambdaArgIndex],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        callArguments = [loweredReceiverID] + scalarArgIDs + [fnPtrExpr, envPtrExpr]
                    } else {
                        callArguments = nil
                    }
                } else {
                    callArguments = nil
                }
                if let callArguments {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_windowedSequence_transform"),
                        arguments: callArguments,
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: replaceFirst(oldValue, newValue) (STDLIB-188)
        // Skip when first arg is a Regex — handled by the STDLIB-REGEX-094 block below.
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgIsRegex = isRegexLikeType(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                sema: sema,
                interner: interner
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType), !firstArgIsRegex {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceFirst"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-FN-060: replaceFirst(oldValue, newValue, ignoreCase) — 3-arg overload
        if args.count == 3, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let thirdArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[2].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(thirdArgType, sema.types.booleanType)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceFirst_ignoreCase"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-FN-068: String.slice(IntRange) / String.slice(Iterable<Int>)
        if args.count == 1, interner.resolve(calleeName) == "slice" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let isRange = sema.bindings.isRangeExpr(args[0].expr)
                let sliceCallee = isRange ? "kk_string_slice_range" : "kk_string_slice_iterable"
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(sliceCallee),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: removeRange(startIndex, endIndex) (STDLIB-TEXT-EDGE-008)
        if args.count == 2, interner.resolve(calleeName) == "removeRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeRange"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: removeRange(range) (STDLIB-TEXT-EDGE-008)
        if args.count == 1, interner.resolve(calleeName) == "removeRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_removeRange_range"),
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replaceRange(range, replacement) (STDLIB-188)
        if args.count == 2, interner.resolve(calleeName) == "replaceRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceRange"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replaceRange(startIndex, endIndex, replacement) (STDLIB-TEXT-FN-062)
        if args.count == 3, interner.resolve(calleeName) == "replaceRange" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceRange_indices"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replace(old, new) (STDLIB-006) / replace(Char, Char) (STDLIB-TEXT-FN-055)
        if args.count == 2, interner.resolve(calleeName) == "replace" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let firstArgType = sema.types.makeNonNullable(
                    sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
                )
                let runtimeCallee: String
                if isRegexLikeType(firstArgType, sema: sema, interner: interner) {
                    runtimeCallee = "kk_string_replace_regex"
                } else if sema.types.isSubtype(firstArgType, sema.types.charType) {
                    runtimeCallee = "kk_string_replace_char"
                } else {
                    runtimeCallee = "kk_string_replace"
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // STDLIB-TEXT-FN-055: replace(old, new, ignoreCase) — 3-arg overload
        if args.count == 3, interner.resolve(calleeName) == "replace" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let firstArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            )
            let thirdArgType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[args[2].expr] ?? sema.types.anyType
            )
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               sema.types.isSubtype(thirdArgType, sema.types.booleanType)
            {
                let runtimeCallee = sema.types.isSubtype(firstArgType, sema.types.charType)
                    ? "kk_string_replace_char_ignoreCase"
                    : "kk_string_replace_ignoreCase"
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(runtimeCallee),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1], loweredArgIDs[2]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: replaceFirst(regex, replacement) (STDLIB-REGEX-094)
        if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType),
               isRegexLikeType(
                   sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType,
                   sema: sema,
                   interner: interner
               ) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_replaceFirst_regex"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // String stdlib: format(vararg args) (STDLIB-006)
        if interner.resolve(calleeName) == "format",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_format"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                func boxedFormatArgument(_ argExpr: ExprID, loweredArgID: KIRExprID) -> KIRExprID {
                    let argType = sema.bindings.exprTypes[argExpr] ?? sema.types.anyType
                    let nonNullArgType = sema.types.makeNonNullable(argType)
                    let boxCallee = BoxingCalleeTable(interner: interner).boxCallee(
                        for: sema.types.kind(of: nonNullArgType),
                        requireNonNull: true
                    )

                    let boxedArg = arena.appendTemporary(type: sema.types.nullableAnyType
                    )
                    if let boxCallee {
                        instructions.append(.call(
                            symbol: nil,
                            callee: boxCallee,
                            arguments: [loweredArgID],
                            result: boxedArg,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    } else {
                        instructions.append(.copy(from: loweredArgID, to: boxedArg))
                    }
                    return boxedArg
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
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_format"),
                    arguments: [loweredReceiverID, packedArgs],
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
