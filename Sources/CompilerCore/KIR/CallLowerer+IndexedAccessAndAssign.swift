
extension CallLowerer {
    // MARK: - Array Operations

    func lowerIndexedAccessExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let receiverID = driver.lowerExpr(
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
            sema: sema
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
                symbol: nil,
                callee: interner.intern("__kk_string_get_flat"),
                arguments: [receiverID, indexID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if let chosenGet = callBinding?.chosenCallee,
           chosenGet != .invalid,
           let signature = sema.symbols.functionSignature(for: chosenGet),
           signature.receiverType != nil
        {
            let loweredIndices = indices.map { indexExpr in
                driver.lowerExpr(
                    indexExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            emitMemberCallInstruction(
                normalized: driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredIndices,
                    callBinding: callBinding,
                    chosenCallee: chosenGet,
                    spreadFlags: Array(repeating: false, count: loweredIndices.count),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
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
                arguments: [receiverID] + loweredIndices
            )
            return result
        }
        // Built-in array get only supports a single Int index
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
                symbol: nil,
                callee: interner.intern("kk_array_get"),
                arguments: [receiverID, indexID],
                result: boxedResult,
                canThrow: false,
                thrownResult: nil
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
            // ByteArray.asUByteArray() preserves signed storage, so normalize
            // the raw byte to UByte at the typed read boundary.
            let rawResult = arena.appendTemporary(type: sema.types.intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get"),
                arguments: [receiverID, indexID],
                result: rawResult,
                canThrow: false,
                thrownResult: nil
            ))
            emitNonThrowingCall(
                callee: interner.intern("kk_int_to_ubyte"),
                arg: rawResult,
                result: result,
                into: &instructions
            )
            return result
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    /// Snapshots an already-lowered operand into a fresh temporary.
    ///
    /// A bare reference to a mutable local (`nameRef`) returns that local's
    /// persistent storage register by identity rather than a value snapshot
    /// (see the `.nameRef` case in `ExprLowerer+ControlFlowAndBlocks.swift`,
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
    /// on every operand of a multi-operand construct as soon as it is
    /// lowered, before lowering the next sibling operand.
    func freezeEvaluationOrderOperand(
        _ id: KIRExprID,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let temp = arena.appendTemporary(type: arena.exprType(id))
        instructions.append(.copy(from: id, to: temp))
        return temp
    }

    /// True when `exprID` is a bare reference to a mutable (`var`) local —
    /// the only shape whose lowered `KIRExprID` aliases a register that a
    /// later-evaluated sibling operand could still mutate in place (see
    /// `freezeEvaluationOrderOperand`). Anything else — a `val`, a literal,
    /// a lambda, a nested call, a property, a value parameter, ... — either
    /// cannot be mutated by a sibling, or is already lowered into its own
    /// fresh value, so freezing it would only add a needless extra copy.
    /// That matters beyond cost: a call argument that is a trailing lambda
    /// passed to an `inline` stdlib function (e.g. `fold`/`reduce` on a
    /// range) is later consumed by the separate inline-lowering pass, which
    /// expects to find the closure construction directly feeding the call;
    /// splicing an unconditional copy in between broke that pattern match
    /// and crashed under `-O2`.
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

    /// Conservatively true when `exprID` could possibly perform a write
    /// (an assignment, an increment/decrement, or a call that might do
    /// either indirectly) while it is evaluated. False only for an
    /// expression built purely from literals, bare reads, and arithmetic/
    /// comparison/logical operators over such expressions — a shape that
    /// can never mutate anything, however deep it nests.
    ///
    /// This exists to avoid freezing a sibling operand needlessly: e.g. in
    /// `result = result + 22`, the rhs `22` cannot mutate `result`, so
    /// there is no aliasing hazard and freezing the lhs would only add a
    /// dead `.copy` that some optimization levels don't fold away (this
    /// was caught by `LLVMOptimizationPipelineTests`'s stack-slot-
    /// elimination probe). `needsEvaluationOrderFreeze` should only cause
    /// a freeze when *this* also returns true for the later-evaluated
    /// sibling(s).
    ///
    /// Bounded by the same depth the expression parser itself enforces
    /// (`ExpressionParser.maxRecursionDepth`), so hitting the bound
    /// conservatively returns true rather than recursing unboundedly.
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

    /// True when any of `exprIDs` might mutate state per
    /// `expressionMayMutateState`.
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
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Built-in array set only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed assign")
        let rawIndexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let indexID = needsEvaluationOrderFreeze(indices[0], ast: ast, sema: sema)
            && expressionMayMutateState(valueExpr, ast: ast)
            ? freezeEvaluationOrderOperand(rawIndexID, arena: arena, instructions: &instructions)
            : rawIndexID
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // A cast to Array<Any?> can make Sema bind the generic `Array.set`
        // member, but indexed assignment still has to use the array runtime
        // entry point. Emitting the source-backed member call here drops the
        // write from the KIR body and leaves the original array unchanged.
        let assignReceiverType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        )
        let assignReceiverIsArrayLike = isConcreteArrayLikeType(
            assignReceiverType,
            sema: sema,
            interner: interner
        )
        if let callBinding = sema.bindings.callBindings[exprID], !assignReceiverIsArrayLike {
            let chosenSet = callBinding.chosenCallee
            var loweredIndices: [KIRExprID] = []
            for (i, indexExpr) in indices.enumerated() {
                if i == 0 {
                    loweredIndices.append(indexID)
                } else {
                    let loweredIndex = driver.lowerExpr(
                        indexExpr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    loweredIndices.append(loweredIndex)
                }
            }
            let loweredArgs = loweredIndices + [valueID]
            let callResult = arena.appendTemporary(type: sema.types.unitType)
            emitMemberCallInstruction(
                normalized: driver.callSupportLowerer.normalizedCallArguments(
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
                ),
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
                arguments: [receiverID] + loweredArgs
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
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, storedValueID],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    // NOTE: isSequenceLikeType is defined once in CallLowerer+MemberCalls.swift
    // and shared across all CallLowerer extensions.

    /// True when `receiverType` is the generic `Array<T>` class specifically, as
    /// opposed to one of the specialized primitive array types (IntArray,
    /// CharArray, ...). Array<T>'s backing store holds boxed elements for
    /// primitive T (mirroring List<T>); the primitive-specialized array types
    /// share the same "kk_array_of"/"kk_array_get"/"kk_array_set" runtime entry
    /// points but store raw values and must never be boxed/unboxed.
    func isGenericArrayReceiverType(_ receiverType: TypeID?, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let receiverType,
              let (_, symbol) = resolveClassTypeSymbol(sema.types.makeNonNullable(receiverType), sema: sema)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "Array"
    }
}
