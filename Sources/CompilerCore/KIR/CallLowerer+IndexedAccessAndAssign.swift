
extension CallLowerer {

    private func isSafeChainIndexedReceiver(_ receiverExpr: ExprID, ast: ASTModule, sema: SemaModule) -> Bool {
        guard !ast.arena.isParenthesized(receiverExpr) else { return false }
        switch ast.arena.expr(receiverExpr) {
        case .safeMemberCall:
            let chosen = sema.bindings.callBinding(for: receiverExpr)?.chosenCallee
                ?? sema.bindings.identifierSymbol(for: receiverExpr)
            guard let chosen else { return false }
            let memberResultType: TypeID?
            if let signature = sema.symbols.functionSignature(for: chosen) {
                memberResultType = signature.returnType
            } else {
                memberResultType = sema.symbols.propertyType(for: chosen)
            }
            return memberResultType.map { sema.types.nullability(of: $0) == .nonNull } ?? false
        case .indexedAccess:
            guard let valueType = sema.bindings.safeChainIndexedValueType(for: receiverExpr) else { return false }
            return sema.types.nullability(of: valueType) == .nonNull
        default:
            return false
        }
    }

    func lowerIndexedAccessExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction],
        precomputedReceiverID: KIRExprID? = nil
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        if precomputedReceiverID == nil, isSafeChainIndexedReceiver(receiverExpr, ast: ast, sema: sema) {
            let safeResultType = boundType ?? sema.types.nullableAnyType
            let safeResult = arena.appendTemporary(type: safeResultType)
            let receiverID = driver.lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: receiverID, target: nonNullLabel))
            let nullValue = arena.appendExpr(.unit, type: safeResultType)
            instructions.append(.constValue(result: nullValue, value: .null))
            instructions.append(.copy(from: nullValue, to: safeResult))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            let nonNullValue = lowerIndexedAccessExpr(
                exprID,
                receiverExpr: receiverExpr,
                indices: indices,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions,
                precomputedReceiverID: receiverID
            )
            instructions.append(.copy(from: nonNullValue, to: safeResult))
            instructions.append(.label(endLabel))
            return safeResult
        }
        let receiverID = precomputedReceiverID ?? driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let receiverIsIntrinsicArray: Bool = if let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) {
            symbol.fqName == [interner.intern("kotlin"), symbol.name]
                && KnownCompilerNames(interner: interner).isArrayLikeName(symbol.name)
        } else {
            false
        }
        let resolvedCallBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: interner.intern("get"),
            argumentExprs: indices,
            sema: sema,
            interner: interner
        ) ?? sema.bindings.callBindings[exprID]
        let chosenGetIsIntrinsic: Bool = if receiverIsIntrinsicArray,
            indices.count == 1,
            let chosenGet = resolvedCallBinding?.chosenCallee,
            let symbol = sema.symbols.symbol(chosenGet),
            symbol.fqName.count == 3,
            symbol.fqName[0] == interner.intern("kotlin"),
            KnownCompilerNames(interner: interner).isArrayLikeName(symbol.fqName[1]),
            symbol.fqName[2] == interner.intern("get"),
            let signature = sema.symbols.functionSignature(for: chosenGet)
        {
            signature.parameterTypes == [sema.types.intType]
        } else {
            false
        }
        // Only the canonical Int-indexed member uses the intrinsic. Its body
        // is this[index], so member dispatch would recurse. Other operator get
        // overloads still dispatch normally, including multi-index extensions.
        let callBinding: CallBinding? = chosenGetIsIntrinsic ? nil : resolvedCallBinding
        let receiverUsesFlatStringABI = sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
        let chosenGetIsSourceBacked = if let chosenGet = callBinding?.chosenCallee {
            sema.symbols.isSourceBackedSymbol(chosenGet)
        } else {
            false
        }
        if indices.count == 1,
           receiverUsesFlatStringABI,
           !chosenGetIsSourceBacked
        {
            let indexID = driver.lowerExpr(
                indices[0],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("__kk_string_get_flat"),
                arguments: [receiverID, indexID],
                result: result,
                canThrow: false
            ))
            return result
        }
        if let chosenGet = callBinding?.chosenCallee,
           chosenGet != .invalid,
           let signature = sema.symbols.functionSignature(for: chosenGet),
           signature.receiverType != nil
        {
            var loweredIndices: [KIRExprID] = []
            for (position, indexExpr) in indices.enumerated() {
                let rawIndexID = driver.lowerExpr(
                    indexExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let laterIndices = indices.dropFirst(position + 1)
                let indexID = needsEvaluationOrderFreeze(indexExpr, ast: ast, sema: sema)
                    && anyExpressionMayMutateState(laterIndices, ast: ast)
                    ? freezeEvaluationOrderOperand(rawIndexID, arena: arena, instructions: &instructions)
                    : rawIndexID
                loweredIndices.append(indexID)
            }
            let normalized = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredIndices,
                callBinding: callBinding,
                chosenCallee: chosenGet,
                spreadFlags: Array(repeating: false, count: loweredIndices.count),
                sourceArgExprs: indices,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
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
            emitMemberCallInstruction(
                normalized: normalized,
                callBinding: callBinding,
                chosenCallee: chosenGet,
                calleeName: interner.intern("get"),
                receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
                result: result,
                isSuperCall: sema.bindings.isSuperCallExpr(exprID),
                qualifiedSuperType: nil,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: [receiverID] + normalized.arguments,
                sourceArgExprs: indices
            )
            return result
        }
        assert(!indices.isEmpty, "indices must not be empty for indexed access")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        // Array<T>'s backing store holds boxed elements for primitive T (mirroring
        // listOf/kk_list_get), unlike IntArray/CharArray/... which store raw
        // primitives directly. Unbox right after the raw read so this result carries
        // the same raw-primitive representation any other primitive-typed KIR value
        // does; otherwise the boxed pointer gets misread as a raw value downstream
        // (e.g. re-boxed a second time at the next Any boundary).
        let receiverIsGenericArray = isGenericArrayReceiverType(nonNullReceiverType, sema: sema, interner: interner)
        if receiverIsGenericArray,
           let elementType = boundType,
           let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
               for: elementType,
               types: sema.types,
               requireNonNull: true
           )
        {
            let boxedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_get"),
                arguments: [receiverID, indexID],
                result: boxedResult,
                canThrow: false
            ))
            emitNonThrowingCall(
                callee: unboxCallee,
                arg: boxedResult,
                result: result,
                into: &instructions
            )
            return result
        }
        if TypeCheckHelpers().arrayElementType(
            for: nonNullReceiverType,
            sema: sema,
            interner: interner
        ) == sema.types.ubyteType {
            let rawResult = arena.appendTemporary(type: sema.types.intType)
            instructions.append(.call(callee: interner.intern("kk_array_get"), arguments: [receiverID, indexID], result: rawResult, canThrow: false))
            emitNonThrowingCall(
                callee: interner.intern("kk_int_to_ubyte"),
                arg: rawResult,
                result: result,
                into: &instructions
            )
            return result
        }
        instructions.append(.call(callee: interner.intern("kk_array_get"), arguments: [receiverID, indexID], result: result, canThrow: false))
        return result
    }

    /// via `localValue(for:)`). KIR instructions execute strictly in the
    /// order they are appended, so if a later-evaluated sibling operand
    /// (e.g. an indexed assignment's value expression, or the right operand
    /// of a binary expression, when it contains `i++`/`++i` on the same
    /// variable this operand already read) mutates that register in place
    /// before the instruction that consumes this operand actually runs, that
    /// instruction observes the mutated value instead of the value at the
    /// point this operand was evaluated. Copying into a fresh temporary
    /// immediately after evaluation freezes the evaluate-once value that
    /// Kotlin's specified left-to-right evaluation order requires. Call this
    func freezeEvaluationOrderOperand(
        _ id: KIRExprID,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let temp = arena.appendTemporary(type: arena.exprType(id))
        instructions.append(.copy(from: id, to: temp))
        return temp
    }

    /// fresh value, so freezing it would only add a needless extra copy.
    /// That matters beyond cost: a call argument that is a trailing lambda
    /// passed to an `inline` stdlib function (e.g. `fold`/`reduce` on a
    /// range) is later consumed by the separate inline-lowering pass, which
    /// expects to find the closure construction directly feeding the call;
    /// splicing an unconditional copy in between broke that pattern match
    func needsEvaluationOrderFreeze(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        guard case .nameRef = ast.arena.expr(exprID),
              let symbol = sema.bindings.identifierSymbols[exprID],
              let symbolInfo = sema.symbols.symbol(symbol)
        else {
            return false
        }
        return symbolInfo.kind == .local && symbolInfo.flags.contains(.mutable)
    }

    func expressionMayMutateState(
        _ exprID: ExprID,
        ast: ASTModule,
        depth: Int = 0
    ) -> Bool {
        guard depth < 64, let expr = ast.arena.expr(exprID) else {
            return true
        }
        switch expr {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral,
             .stringLiteral, .nameRef:
            return false
        case let .binary(_, lhs, rhs, _):
            return expressionMayMutateState(lhs, ast: ast, depth: depth + 1)
                || expressionMayMutateState(rhs, ast: ast, depth: depth + 1)
        case let .unaryExpr(_, operand, _):
            return expressionMayMutateState(operand, ast: ast, depth: depth + 1)
        default:
            return true
        }
    }

    func anyExpressionMayMutateState<S: Sequence>(
        _ exprIDs: S,
        ast: ASTModule
    ) -> Bool where S.Element == ExprID {
        exprIDs.contains { expressionMayMutateState($0, ast: ast) }
    }

    func lowerIndexedAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let rawReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let receiverID = needsEvaluationOrderFreeze(receiverExpr, ast: ast, sema: sema)
            && anyExpressionMayMutateState(indices + [valueExpr], ast: ast)
            ? freezeEvaluationOrderOperand(rawReceiverID, arena: arena, instructions: &instructions)
            : rawReceiverID
        assert(!indices.isEmpty, "indices must not be empty for indexed assign")
        var loweredIndices: [KIRExprID] = []
        for (position, indexExpr) in indices.enumerated() {
            let rawIndexID = driver.lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let laterOperands = indices.dropFirst(position + 1) + [valueExpr]
            let indexID = needsEvaluationOrderFreeze(indexExpr, ast: ast, sema: sema)
                && anyExpressionMayMutateState(laterOperands, ast: ast)
                ? freezeEvaluationOrderOperand(rawIndexID, arena: arena, instructions: &instructions)
                : rawIndexID
            loweredIndices.append(indexID)
        }
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let assignReceiverType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        )
        let assignReceiverIsArrayLike = isConcreteArrayLikeType(
            assignReceiverType,
            sema: sema,
            interner: interner
        )
        let resolvedCallBinding = sema.bindings.callBindings[exprID]
        let chosenSetIsIntrinsic: Bool = if assignReceiverIsArrayLike,
            indices.count == 1,
            let chosenSet = resolvedCallBinding?.chosenCallee,
            let symbol = sema.symbols.symbol(chosenSet),
            symbol.fqName.count == 3,
            symbol.fqName[0] == interner.intern("kotlin"),
            KnownCompilerNames(interner: interner).isArrayLikeName(symbol.fqName[1]),
            symbol.fqName[2] == interner.intern("set"),
            let signature = sema.symbols.functionSignature(for: chosenSet)
        {
            signature.parameterTypes.count == 2
                && signature.parameterTypes[0] == sema.types.intType
        } else {
            false
        }
        if let callBinding = resolvedCallBinding, !chosenSetIsIntrinsic {
            let chosenSet = callBinding.chosenCallee
            let loweredArgs = loweredIndices + [valueID]
            let normalizedSetArguments = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgs,
                callBinding: callBinding,
                chosenCallee: chosenSet,
                spreadFlags: Array(repeating: false, count: loweredArgs.count),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let callResult = arena.appendTemporary(type: sema.types.unitType)
            emitMemberCallInstruction(
                normalized: normalizedSetArguments,
                callBinding: callBinding,
                chosenCallee: chosenSet,
                calleeName: interner.intern("set"),
                receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
                result: callResult,
                isSuperCall: sema.bindings.isSuperCallExpr(exprID),
                qualifiedSuperType: nil,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: [receiverID] + normalizedSetArguments.arguments
            )
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // arr[i] = value on a generic Array<T> must box a primitive value before
        // storing it, matching how arrayOf(...) boxes elements at construction time
        // (packVarargArguments) and how arr[i] unboxes on read (above). Leaving this
        // unboxed would corrupt the array with a mix of boxed and raw elements.
        let assignReceiverIsGenericArray = isGenericArrayReceiverType(
            sema.bindings.exprTypes[receiverExpr],
            sema: sema,
            interner: interner
        )
        let storedValueID: KIRExprID
        if assignReceiverIsGenericArray, let valueType = arena.exprType(valueID) {
            storedValueID = boxValueForAnySlot(
                valueID,
                sourceType: valueType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                sema: sema,
                into: &instructions
            )
        } else {
            storedValueID = valueID
        }
        instructions.append(.call(
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, loweredIndices[0], storedValueID],
            result: nil,
            canThrow: false
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// (IntArray, CharArray, ...) share the same "kk_array_of"/"kk_array_get"/
    /// "kk_array_set" runtime entry points but store raw values and must never
    /// be boxed/unboxed.
    func isGenericArrayReceiverType(_ receiverType: TypeID?, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let receiverType,
              let (_, symbol) = resolveClassTypeSymbol(sema.types.makeNonNullable(receiverType), sema: sema)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "Array"
    }
}
