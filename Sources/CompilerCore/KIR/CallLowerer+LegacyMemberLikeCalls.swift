// swiftlint:disable file_length

/// Legacy stdlib/member special-case lowering path.
///
/// This remains deliberately isolated while narrower families continue to move out.
extension CallLowerer {
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// This shared lowering path still centralizes legacy stdlib/member special cases.
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
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // swiftlint:enable cyclomatic_complexity function_body_length
        if let foldedConst = tryFoldConstMemberProperty(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            requireNonNullableReceiver: requireNonNullableReceiverForConstFold,
            sema: sema,
            arena: arena,
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
        if let staticMemberValue = tryLowerClassNameMemberValueExpr(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            instructions: &instructions
        ) {
            return staticMemberValue
        }

        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let argInstructionStart = instructions.count
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let normalizedArgIDs: [KIRExprID] = {
            guard isCollectionHOFCallee(calleeName, interner: interner) else {
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
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        if args.count == 1,
           interner.resolve(calleeName) == "withDefault"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if isMapLikeType(receiverType, sema: sema, interner: interner) {
                let runtimeArguments: [KIRExprID]
                if normalizedArgIDs.count >= 2 {
                    runtimeArguments = [loweredReceiverID, normalizedArgIDs[0], normalizedArgIDs[1]]
                } else if let defaultValueArg = normalizedArgIDs.first {
                    let split = splitCallableLambdaArgument(
                        defaultValueArg,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    runtimeArguments = [loweredReceiverID, split.fnPtrExpr, split.envPtrExpr]
                } else {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    runtimeArguments = [loweredReceiverID, zeroExpr, zeroExpr]
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_map_withDefault"),
                    arguments: runtimeArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        let chosenBase64Callee: SymbolID? = {
            guard let selected = sema.bindings.callBindings[exprID]?.chosenCallee, selected != .invalid else {
                return nil
            }
            return selected
        }()

        if tryLowerBase64MemberCall(
            receiverExpr: receiverExpr,
            loweredReceiverID: loweredReceiverID,
            calleeName: calleeName,
            chosenCallee: chosenBase64Callee,
            argExprIDs: args.map(\.expr),
            loweredArgIDs: loweredArgIDs,
            argInstructionStart: argInstructionStart,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return result
        }

        if args.count == 1,
           interner.resolve(calleeName) == "sortedWith"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isComparatorLambdaArg = ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false
            if isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner),
               !isComparatorLambdaArg
            {
                let sortedWithArguments = adaptComparatorBackedCollectionArguments(
                    loweredCallee: interner.intern("kk_list_sortedWith"),
                    finalArguments: [loweredReceiverID] + normalizedArgIDs,
                    sourceArgExprs: args.map(\.expr),
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_list_sortedWith"),
                    arguments: sortedWithArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                ))
                return result
            }
        }

        if args.count == 1,
           interner.resolve(calleeName) == "sortedArrayWith"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee = interner.intern("kk_array_sortedArrayWith")
                let sortedArrayWithArguments = adaptComparatorBackedCollectionArguments(
                    loweredCallee: runtimeCallee,
                    finalArguments: [loweredReceiverID] + normalizedArgIDs,
                    sourceArgExprs: args.map(\.expr),
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: sortedArrayWithArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: arena.appendExpr(
                        .temporary(Int32(arena.expressions.count)),
                        type: sema.types.nullableAnyType
                    )
                ))
                return result
            }
        }

        if let r = tryLowerCollectionStdlibMemberCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: requireNonNullableReceiverForConstFold,
            chosenBase64Callee: chosenBase64Callee,
            boundType: boundType,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            normalizedArgIDs: normalizedArgIDs,
            result: result,
            instructions: &instructions
        ) { return r }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isRangeLikeReceiver = sema.bindings.isRangeExpr(receiverExpr) || {
                guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                let name = interner.resolve(symbol.name)
                return name == "IntProgression"
                    || name == "LongProgression"
                    || name == "LongRange"
                    || name == "CharProgression"
                    || name == "UIntRange"
                    || name == "UIntProgression"
                    || name == "ULongProgression"
            }()
            let isLongRange = nonNullReceiverType == sema.types.longType
            if isRangeLikeReceiver {
                let runtimeGetter: InternedString? = switch interner.resolve(calleeName) {
                case "start":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : (isLongRange ? "kk_long_range_first" : "kk_range_first")))
                case "end":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : (isLongRange ? "kk_long_range_last" : "kk_range_last")))
                case "endExclusive":
                    interner.intern("kk_range_endExclusive")
                case "first":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : (isLongRange ? "kk_long_range_first" : "kk_range_first")))
                case "last":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : (isLongRange ? "kk_long_range_last" : "kk_range_last")))
                case "step":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_step"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_step"
                            : (isLongRange ? "kk_long_range_step" : "kk_range_step")))
                default:
                    nil
                }
                if let runtimeGetter {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeGetter,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
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
            loweredReceiverID: loweredReceiverID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedMemberProperty
        }

        if args.isEmpty,
           calleeName == interner.intern("step")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString = if sema.bindings.isULongRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.ulongType
            {
                interner.intern("kk_ulong_range_step")
            } else if sema.bindings.isUIntRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.uintType
            {
                interner.intern("kk_uint_range_step")
            } else {
                interner.intern("kk_range_step")
            }
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

        if let r = tryLowerPrimitiveMemberCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: requireNonNullableReceiverForConstFold,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            normalizedArgIDs: normalizedArgIDs,
            result: result,
            instructions: &instructions
        ) { return r }

        if let r = tryLowerStringStdlibMemberCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: requireNonNullableReceiverForConstFold,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            normalizedArgIDs: normalizedArgIDs,
            result: result,
            instructions: &instructions
        ) { return r }

        if let r = tryLowerStringBuilderMemberCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: requireNonNullableReceiverForConstFold,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            normalizedArgIDs: normalizedArgIDs,
            result: result,
            instructions: &instructions
        ) { return r }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)

        // Extract qualified super type information for super<Interface> calls
        var qualifiedSuperType: SymbolID?
        if isSuperCall, case let .superRef(interfaceQualifier, _) = ast.arena.expr(receiverExpr) {
            if let qualifier = interfaceQualifier {
                // Find the interface symbol that matches the qualifier
                if let currentReceiverType = sema.bindings.exprTypes[receiverExpr],
                   case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(currentReceiverType)) {
                    let classSymbol = classType.classSymbol
                    let directSupertypes = sema.symbols.directSupertypes(for: classSymbol)
                    let qualifierStr = interner.resolve(qualifier)
                    for superID in directSupertypes {
                        guard let superSym = sema.symbols.symbol(superID) else { continue }
                        if superSym.kind == SymbolKind.interface && interner.resolve(superSym.name) == qualifierStr {
                            qualifiedSuperType = superID
                            break
                        }
                    }
                }
            }
        }

        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            argumentExprs: args.map(\.expr),
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        if qualifiedSuperType == nil,
           isSuperCall,
           case let .superRef(interfaceQualifier?, _) = ast.arena.expr(receiverExpr),
           let chosenCallee = callBinding?.chosenCallee,
           chosenCallee != .invalid,
           let ownerSymbol = sema.symbols.parentSymbol(for: chosenCallee),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .interface,
           interner.resolve(ownerInfo.name) == interner.resolve(interfaceQualifier)
        {
            qualifiedSuperType = ownerSymbol
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
            sourceArgExprs: args.map(\.expr),
            sourceArgLabels: args.map(\.label)
        )
        return result
    }
}
