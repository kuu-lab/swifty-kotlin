// swiftlint:disable file_length

extension CallLowerer {
    static func isSourceBackedLinkName(_ linkName: String?) -> Bool {
        guard let linkName, !linkName.isEmpty else { return true }
        return linkName.hasPrefix("kk_fn_")
    }

    static let sourceBackedIterableCollectionMemberNames: Set<String> = [
        "all", "any", "none", "firstNotNullOf", "firstNotNullOfOrNull", "joinTo", "joinToString",
        "containsAll", "count", "isNotEmpty", "intersect", "last", "lastIndexOf", "lastOrNull",
        "minus", "minusElement", "plus", "plusElement", "random", "randomOrNull",
        "min", "minBy", "minByOrNull", "minOf", "minOfOrNull", "minOfWith",
        "minOfWithOrNull", "minOrNull", "minWith", "minWithOrNull",
        "requireNoNulls", "reduceRight", "reduceRightIndexed", "reduceRightIndexedOrNull",
        "reduceRightOrNull", "sumBy", "sumByDouble", "subtract", "toCollection", "toHashSet",
        "toBooleanArray", "toByteArray", "toCharArray", "toDoubleArray", "toFloatArray", "toIntArray",
        "toList", "toLongArray", "toMap", "toMutableList", "toMutableSet", "toSet", "toShortArray",
        "toTypedArray", "toUByteArray", "toUIntArray", "toULongArray", "toUShortArray", "union", "zipWithNext",
        "filter", "filterIndexed", "filterIndexedTo", "filterIsInstance",
        "filterIsInstanceTo", "filterNot", "filterNotNull", "filterNotNullTo", "filterNotTo", "filterTo",
        "indexOf", "indexOfFirst", "indexOfLast",
        "shuffled",
        "distinct", "distinctBy", "flatten",
        "max", "maxBy", "maxByOrNull", "maxOf", "maxOfOrNull", "maxOfWith",
        "maxOfWithOrNull", "maxOrNull", "maxWith", "maxWithOrNull",
        "groupBy", "groupByTo",
    ]

    static let sourceBackedStringMemberNames: Set<String> = [
        "split", "replace", "replaceFirst",
        "get", "compareTo", "intern", "equals",
        "first", "firstOrNull", "last", "lastOrNull",
        "single", "singleOrNull", "getOrNull",
        "format", "concat", "plus",
        "lowercase", "uppercase", "normalize", "isNormalized",
        "codePointCount", "toByteArray", "encodeToByteArray", "byteInputStream",
    ]

    static let sourceBackedListSearchNames: Set<String> = [
        "find", "findLast", "indexOf", "indexOfFirst", "indexOfLast",
        "lastIndexOf", "contains", "containsAll", "any", "all", "none",
        "count", "binarySearch", "binarySearchBy",
    ]

    static let sourceBackedArrayNames: Set<String> = [
        "IntArray", "LongArray", "ShortArray", "ByteArray",
        "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
        "UByteArray", "UShortArray", "UIntArray", "ULongArray", "Array",
    ]

    // swiftlint:disable cyclomatic_complexity function_body_length
    func lowerMemberLikeCallExpr(
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
        prependReceiverForUnresolvedCollectionCall: Bool,
        instructions: inout [KIRInstruction],
        loweredReceiverOverride: KIRExprID? = nil
    ) -> KIRExprID {
        // swiftlint:enable cyclomatic_complexity function_body_length
        // BUG-inner-outer: `outer.Inner(args)` resolves to Inner's own
        // constructor (`collectInnerClassConstructorCandidates`), but every
        // path below treats a resolved `chosenCallee` as an ordinary member
        // function and splices the *lowered receiver itself* in as the
        // call's first argument (`appendReceiverToMemberArguments`) --
        // which for a constructor means using `outer`'s own instance as if
        // it already were the freshly allocated `Inner`, instead of
        // allocating a real `Inner` object and storing `outer` into its
        // `$outer` link. Intercept before any of the special cases below
        // lower `receiverExpr` for their own (inapplicable, for a
        // constructor target) purposes.
        if let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           chosenCallee != .invalid,
           sema.symbols.symbol(chosenCallee)?.kind == .constructor,
           let innerClassSymbol = sema.symbols.parentSymbol(for: chosenCallee),
           sema.symbols.symbol(innerClassSymbol)?.flags.contains(.innerClass) == true
        {
            return lowerInnerClassConstructorMemberCall(
                exprID,
                receiverExpr: receiverExpr,
                chosenCtor: chosenCallee,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        if let foldedConst = tryFoldConstMemberProperty(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            requireNonNullableReceiver: requireNonNullableReceiverForConstFold,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return foldedConst
        }
        if let constValue = sema.bindings.constExprValue(for: exprID) {
            let constResult = arena.appendExpr(
                constValue,
                type: sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            )
            instructions.append(.constValue(result: constResult, value: constValue))
            return constResult
        }
        if let foldedString = tryFoldBuiltinStringIndentTrimCall(
            exprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return foldedString
        }
        if let staticMemberValue = tryLowerClassNameMemberValueExpr(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return staticMemberValue
        }

        let boundType = sema.bindings.exprTypes[exprID]
        let calleeNameStr = interner.resolve(calleeName)
        let loweredReceiverID = loweredReceiverOverride ?? driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let argumentCallBinding = sema.bindings.callBindings[exprID]
        let loweredArgIDs = args.enumerated().map { argumentIndex, argument in
            let previousAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
                argumentExpr: argument.expr,
                argumentIndex: argumentIndex,
                ast: ast,
                sema: sema,
                callBinding: argumentCallBinding,
                chosen: argumentCallBinding?.chosenCallee
            )
            defer { driver.ctx.pendingLambdaNonLocalReturnAllowance = previousAllowance }
            let rawArgID = driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            // see needsEvaluationOrderFreeze's doc comment for why an
            // unconditional freeze here is unsafe for trailing-lambda
            // arguments to inline functions (e.g. range `fold`/`reduce`).
            return needsEvaluationOrderFreeze(argument.expr, ast: ast, sema: sema)
                && anyExpressionMayMutateState(args[(argumentIndex + 1)...].map(\.expr), ast: ast)
                ? freezeEvaluationOrderOperand(rawArgID, arena: arena, instructions: &instructions)
                : rawArgID
        }
        let memberReceiverType = sema.bindings.exprTypes[receiverExpr]
            ?? arena.exprType(loweredReceiverID)
        if let memberReceiverType,
           CallLowerer.kclassMembers.contains(calleeNameStr),
           isKClassReceiverType(memberReceiverType, sema: sema, interner: interner)
        {
            return lowerKClassRuntimeMemberCall(
                exprID,
                kclassExpr: loweredReceiverID,
                memberName: calleeNameStr,
                valueArgs: calleeNameStr == "isInstance" ? loweredArgIDs : [],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        let chosenCalleeForArgumentAdaptation = sema.bindings.callBindings[exprID]?.chosenCallee
        let isSourceBackedMemberCall: Bool = {
            guard let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            guard sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) else {
                return false
            }
            // KUU-1766: a range call with one omitted index must retain its
            // selected Kotlin overload/default stub. The name/arity table
            // otherwise treats that Int argument as a Charset tag.
            if calleeNameStr == "encodeToByteArray",
               sema.symbols.functionSignature(for: chosenCallee)?.parameterTypes
                    == [sema.types.intType, sema.types.intType]
            {
                return true
            }
            return Self.sourceBackedStringMemberNames.contains(calleeNameStr)
        }()
        let isSourceBackedIterableCollectionCall: Bool = {
            guard let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let memberName = calleeNameStr
            let knownNames = KnownCompilerNames(interner: interner)
            if memberName == "plus" {
                guard let signature = sema.symbols.functionSignature(for: chosenCallee),
                      let declaredReceiver = signature.receiverType,
                      let (_, declaredReceiverSymbol) = resolveClassTypeSymbol(
                          sema.types.makeNonNullable(declaredReceiver),
                          sema: sema
                      )
                else {
                    return false
                }
                return declaredReceiverSymbol.fqName == knownNames.kotlinCollectionsIterableFQName
            }
            if memberName == "contains",
               let signature = sema.symbols.functionSignature(for: chosenCallee),
               let declaredReceiver = signature.receiverType,
               let (_, declaredReceiverSymbol) = resolveClassTypeSymbol(
                   sema.types.makeNonNullable(declaredReceiver),
                   sema: sema
               ),
               declaredReceiverSymbol.fqName == knownNames.kotlinCollectionsIterableFQName
            {
                return true
            }
            if Self.sourceBackedIterableCollectionMemberNames.contains(memberName) {
                return true
            }
            if calleeNameStr == "zip" {
                if args.count >= 2 {
                    return true
                }
                guard let firstArgument = args.first,
                      let firstArgumentType = sema.bindings.exprTypes[firstArgument.expr]
                else {
                    return false
                }
                if isGenericKotlinArrayType(
                    sema.types.makeNonNullable(firstArgumentType),
                    sema: sema,
                    interner: interner
                ) {
                    return true
                }

                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                return isIterableOrCollectionInterfaceType(
                    sema.types.makeNonNullable(receiverType),
                    sema: sema,
                    interner: interner
                )
            }
            guard Self.sourceBackedListSearchNames.contains(calleeNameStr) else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            return isConcreteListLikeType(
                sema.types.makeNonNullable(receiverType),
                sema: sema,
                interner: interner
            )
        }()
        let isSourceBackedArrayCopyCall: Bool = {
            guard let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let knownNames = KnownCompilerNames(interner: interner)
            return knownNames.sourceBackedArrayCopyFQNames.contains(symbol.fqName)
        }()
        let isSourceBackedArrayToListCall: Bool = {
            guard calleeNameStr == "toList",
                  let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            guard let (_, receiverSymbol) = resolveClassTypeSymbol(
                sema.types.makeNonNullable(receiverType), sema: sema
            ) else {
                return false
            }
            return Self.sourceBackedArrayNames.contains(interner.resolve(receiverSymbol.name))
        }()
        // `kk_array_toMutableList` shortcut, which boxed every element as a
        // plain word and lost Long/ULong's type-specific null-sentinel and
        // signedness handling (e.g. `longArrayOf(Long.MIN_VALUE).toMutableList()`
        // read back as `null`, `ulongArrayOf(ULong.MAX_VALUE)...` as `-1`).
        let isSourceBackedArrayToMutableListCall: Bool = {
            guard calleeNameStr == "toMutableList",
                  let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            guard let (_, receiverSymbol) = resolveClassTypeSymbol(
                sema.types.makeNonNullable(receiverType), sema: sema
            ) else {
                return false
            }
            return Self.sourceBackedArrayNames.contains(interner.resolve(receiverSymbol.name))
        }()
        let isSourceBackedArrayConversionCall: Bool = {
            let memberName = calleeNameStr
            guard ["sliceArray", "reversedArray", "asList", "toTypedArray"].contains(memberName),
                  let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            return isConcreteArrayLikeType(
                sema.types.makeNonNullable(receiverType),
                sema: sema,
                interner: interner
            )
        }()
        let isSourceBackedArrayIterableCall: Bool = {
            guard let chosenCallee = chosenCalleeForArgumentAdaptation,
                  sema.symbols.isSourceBackedSymbol(chosenCallee),
                  let declaredReceiver = sema.symbols.functionSignature(for: chosenCallee)?.receiverType
            else {
                return false
            }
            return isConcreteArrayLikeType(declaredReceiver, sema: sema, interner: interner)
        }()
        let shouldAdaptCollectionHOFArguments: Bool = {
            guard isCollectionHOFCallee(calleeName, interner: interner) else {
                return false
            }
            guard let chosenCallee = chosenCalleeForArgumentAdaptation, chosenCallee != .invalid else {
                return true
            }
            // `Result.fold(onSuccess, onFailure)` takes two callbacks, but the
            // (fnPtr, closureRaw) pairs produced here are still subject to
            // parameter-mapping normalization, which keeps one argument per
            // declared parameter and therefore drops the onFailure pair.
            // emitMemberCallInstruction expands both callbacks after
            // normalization, so leave the lambdas untouched here.
            if sema.symbols.externalLinkName(for: chosenCallee) == "kk_runtime_result_fold" {
                return false
            }
            if !Self.isSourceBackedLinkName(sema.symbols.externalLinkName(for: chosenCallee)) {
                return true
            }
            return !sema.symbols.isSourceBackedSymbol(chosenCallee)
        }()
        let normalizedArgIDs: [KIRExprID] = {
            guard shouldAdaptCollectionHOFArguments else {
                return loweredArgIDs
            }
            let closureAdapted = addCollectionHOFClosureArguments(
                loweredArgIDs: loweredArgIDs,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return adaptComparatorFactoryArgumentsForCollectionHOF(
                calleeName: calleeName,
                loweredArgIDs: closureAdapted,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }()
        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            argumentExprs: args.map(\.expr),
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        let preservesErasedGenericResult = kirShouldCheckErasedGenericCallResult(
            exprID: exprID,
            boundType: boundType,
            sema: sema,
            erasedLambdaReturnClaims: driver.ctx.erasedLambdaReturnClaimStack
        )
        let result = arena.appendTemporary(
            type: preservesErasedGenericResult
                ? sema.types.nullableAnyType
                : (boundType ?? sema.types.anyType)
        )
        let chosenBase64Callee: SymbolID? = {
            guard let selected = sema.bindings.callBindings[exprID]?.chosenCallee, selected != .invalid else {
                return nil
            }
            return selected
        }()

        let isSourceBackedSequenceCall: Bool = {
            guard let chosenBase64Callee,
                  let symbol = sema.symbols.symbol(chosenBase64Callee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenBase64Callee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            return isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
        }()
        let isSourceBackedTerminalCall: Bool = {
            guard let chosenBase64Callee,
                  let symbol = sema.symbols.symbol(chosenBase64Callee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenBase64Callee)
            else {
                return false
            }
            return true
        }()

        if let lowered = lowerLegacyReduceRightOrNullFallback(
            receiverExpr: receiverExpr,
            calleeNameStr: calleeNameStr,
            args: args,
            sema: sema,
            interner: interner,
            chosenBase64Callee: chosenBase64Callee,
            loweredReceiverID: loweredReceiverID,
            normalizedArgIDs: normalizedArgIDs,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let lowered = lowerLegacyRangeMemberRead(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let storedObjectProperty = tryLowerObjectLiteralStoredPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedObjectProperty
        }

        if let enumEntryProperty = tryLowerEnumEntryPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return enumEntryProperty
        }

        if let externalMemberProperty = tryLowerExternalMemberPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return externalMemberProperty
        }

        if let storedMemberProperty = tryLowerStoredMemberPropertyRead(
            exprID,
            receiverExpr: receiverExpr,
            loweredReceiverID: loweredReceiverID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return storedMemberProperty
        }

        if let lowered = lowerLegacyRangeStepMember(
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let lowered = lowerLegacyPrimitiveMemberOperatorCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            calleeNameStr: calleeNameStr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            chosenCalleeForArgumentAdaptation: chosenCalleeForArgumentAdaptation,
            requireNonNullableReceiverForConstFold: requireNonNullableReceiverForConstFold,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let lowered = lowerLegacyIntLongToStringCall(
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let lowered = lowerLegacyAnyFallbackMemberCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeNameStr: calleeNameStr,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let lowered = lowerLegacyPrimitiveConversionCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeNameStr: calleeNameStr,
            args: args,
            sema: sema,
            interner: interner,
            arena: arena,
            loweredReceiverID: loweredReceiverID,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let lowered = lowerLegacyStringLengthCall(
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            result: result,
            instructions: &instructions
        ) {
            return lowered
        }

        if let lowered = lowerLegacyCharCodeCall(
            receiverExpr: receiverExpr,
            calleeNameStr: calleeNameStr,
            args: args,
            sema: sema,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            result: result,
            chosenCallee: chosenCalleeForArgumentAdaptation,
            instructions: &instructions
        ) {
            return lowered
        }

        if !isSourceBackedMemberCall,
           let tableDrivenStringMember = tryLowerTableDrivenStringMemberCall(
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            normalizedArgIDs: normalizedArgIDs,
            result: result,
            instructions: &instructions
        ) {
            return tableDrivenStringMember
        }

        if !isSourceBackedMemberCall, !isSourceBackedIterableCollectionCall, !isSourceBackedArrayIterableCall {
            if let lowered = lowerLegacyCollectionIsNullOrEmptyCall(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                calleeNameStr: calleeNameStr,
                args: args,
                sema: sema,
                interner: interner,
                chosenCalleeForArgumentAdaptation: chosenCalleeForArgumentAdaptation,
                loweredReceiverID: loweredReceiverID,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacyZeroArgStringMemberCall(
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                sema: sema,
                arena: arena,
                interner: interner,
                loweredReceiverID: loweredReceiverID,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacySingleArgStringMemberCall(
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                sema: sema,
                arena: arena,
                interner: interner,
                loweredReceiverID: loweredReceiverID,
                loweredArgIDs: loweredArgIDs,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacySingleArgArrayMemberCall(
                receiverExpr: receiverExpr,
                calleeNameStr: calleeNameStr,
                args: args,
                sema: sema,
                arena: arena,
                interner: interner,
                loweredReceiverID: loweredReceiverID,
                normalizedArgIDs: normalizedArgIDs,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacySequenceIterableSingleArgFallback(
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                sema: sema,
                arena: arena,
                interner: interner,
                isSourceBackedTerminalCall: isSourceBackedTerminalCall,
                isSourceBackedSequenceCall: isSourceBackedSequenceCall,
                loweredReceiverID: loweredReceiverID,
                normalizedArgIDs: normalizedArgIDs,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacySingleArgListMemberCall(
                receiverExpr: receiverExpr,
                calleeNameStr: calleeNameStr,
                args: args,
                sema: sema,
                interner: interner,
                chosenBase64Callee: chosenBase64Callee,
                loweredReceiverID: loweredReceiverID,
                normalizedArgIDs: normalizedArgIDs,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacyRegexMemberCall(
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                sema: sema,
                interner: interner,
                chosenBase64Callee: chosenBase64Callee,
                loweredReceiverID: loweredReceiverID,
                normalizedArgIDs: normalizedArgIDs,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacyListWindowChunkCall(
                receiverExpr: receiverExpr,
                calleeNameStr: calleeNameStr,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                chosenCallee: callBinding?.chosenCallee,
                loweredReceiverID: loweredReceiverID,
                normalizedArgIDs: normalizedArgIDs,
                parameterMapping: callBinding?.parameterMapping ?? [:],
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacyZeroArgArrayConversionCall(
                receiverExpr: receiverExpr,
                calleeNameStr: calleeNameStr,
                args: args,
                sema: sema,
                interner: interner,
                isSourceBackedArrayToListCall: isSourceBackedArrayToListCall,
                isSourceBackedArrayToMutableListCall: isSourceBackedArrayToMutableListCall,
                isSourceBackedArrayConversionCall: isSourceBackedArrayConversionCall,
                isSourceBackedArrayCopyCall: isSourceBackedArrayCopyCall,
                loweredReceiverID: loweredReceiverID,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacySequenceIterableZeroArgFallback(
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                sema: sema,
                arena: arena,
                interner: interner,
                isSourceBackedTerminalCall: isSourceBackedTerminalCall,
                isSourceBackedSequenceCall: isSourceBackedSequenceCall,
                loweredReceiverID: loweredReceiverID,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
            if let lowered = lowerLegacyStringFormatCall(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                args: args,
                sema: sema,
                arena: arena,
                interner: interner,
                loweredReceiverID: loweredReceiverID,
                loweredArgIDs: loweredArgIDs,
                result: result,
                instructions: &instructions
            ) {
                return lowered
            }
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)

        var qualifiedSuperType: SymbolID?
        if isSuperCall,
           case .superRef(.some, _, _) = ast.arena.expr(receiverExpr),
           let receiverType = sema.bindings.exprTypes[receiverExpr],
           let classType = resolveClassType(receiverType, sema: sema)
        {
            qualifiedSuperType = classType.classSymbol
        }

        let chosen: SymbolID? = if let chosenCallee = callBinding?.chosenCallee, chosenCallee != .invalid {
            chosenCallee
        } else {
            SymbolID?.none
        }
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: normalizedArgIDs,
            callBinding: callBinding,
            chosenCallee: chosen,
            spreadFlags: args.map(\.isSpread),
            argumentLabels: args.map(\.label),
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        var finalArguments = normalized.arguments
        appendReceiverToMemberArguments(
            loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            chosenCallee: chosen,
            prependReceiverForUnresolvedCollectionCall: prependReceiverForUnresolvedCollectionCall,
            sema: sema,
            interner: interner,
            arguments: &finalArguments
        )
        emitMemberCallInstruction(
            normalized: normalized,
            callBinding: callBinding,
            chosenCallee: chosen,
            calleeName: calleeName,
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: loweredReceiverID),
            result: result,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: finalArguments,
            sourceArgumentIDs: loweredArgIDs,
            sourceArgExprs: args.map(\.expr),
            sourceArgLabels: args.map(\.label),
            callExprID: exprID
        )
        return result
    }

    private func tryFoldBuiltinStringIndentTrimCall(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard ConstantCollector.isBuiltinStringIndentTrimCall(
            exprID, ast: ast, sema: sema, interner: interner
        ) else {
            return nil
        }
        var collector = driver.constantCollector
        collector.resolvedConstant = { constantExpr in
            ConstantCollector.compileTimeConstantRef(constantExpr, ast: ast, sema: sema)
        }
        collector.canFoldMemberCall = { candidate in
            ConstantCollector.isBuiltinStringIndentTrimCall(
                candidate, ast: ast, sema: sema, interner: interner
            )
        }
        guard let value = collector.literalConstantExpr(exprID, ast: ast, interner: interner),
              case .stringLiteral = value
        else {
            return nil
        }
        let result = arena.appendExpr(
            value,
            type: sema.bindings.exprType(for: exprID) ?? sema.types.stringType
        )
        instructions.append(.constValue(result: result, value: value))
        return result
    }
}
