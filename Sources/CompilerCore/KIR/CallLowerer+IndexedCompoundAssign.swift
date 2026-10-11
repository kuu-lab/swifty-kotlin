
extension CallLowerer {
    // MARK: - Array Operations

    func lowerIndexedCompoundAssignExpr(
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
        guard let expr = ast.arena.expr(exprID),
              case let .indexedCompoundAssign(op, _, _, _, _) = expr
        else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }

        // Conceptual desugaring: a[i] += v
        //   1) t = kk_array_get(a, i)
        //   2) t' = kk_op_*(t, v)      // appropriate kk_op_* for the compound operator,
        //                              // or the element's own operator bound by Sema
        //   3) kk_array_set(a, i, t')  // skipped for an in-place `plusAssign`
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // KSWIFTK-BUG: when Sema resolved a custom (or source-backed member,
        // e.g. MutableList) get()/set() pair for this compound assign, both
        // halves must dispatch through those member calls instead of the raw
        // array runtime below — otherwise the write silently lands on the
        // receiver's own raw memory layout instead of the container it
        // actually indexes into (bindIndexedCompoundAssignSetOperator only
        // binds this for a non-array-like receiver, so genuine
        // Array<T>/IntArray/... always fall through to the raw path).
        let elementOperator = sema.bindings.indexedCompoundAssignElementOperatorBinding(for: exprID)
        let operatorBinding = sema.bindings.indexedCompoundAssignOperatorBinding(for: exprID)
        // A get()-only receiver is valid for an in-place `plusAssign`, which
        // never writes back, so Sema binds no set() for it.
        let usesInPlaceElementOperatorWithoutSet = elementOperator?.kind == .inPlace
            && !isConcreteArrayLikeType(
                sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType),
                sema: sema,
                interner: interner
            )
        if let getCallBinding = sema.bindings.callBinding(for: exprID),
           operatorBinding != nil || usesInPlaceElementOperatorWithoutSet
        {
            return lowerIndexedCompoundAssignExprViaCustomOperator(
                exprID,
                op: op,
                receiverExpr: receiverExpr,
                indices: indices,
                valueExpr: valueExpr,
                receiverID: receiverID,
                getCallBinding: getCallBinding,
                operatorBinding: operatorBinding,
                elementOperator: elementOperator,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // Built-in array compound assign only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed compound assign")
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
        // Derive element type from the receiver's array type.
        // Mirrors TypeCheckHelpers.arrayElementType logic.
        let receiverBoundType = sema.bindings.exprTypes[receiverExpr]
        // Array<T>'s backing store holds boxed elements for primitive T (mirroring
        // lowerIndexedAccessExpr / lowerIndexedAssignExpr); IntArray/CharArray/...
        // keep storing raw primitives directly. Without unbox-before-op and
        // box-before-store here, a[i] += v on Array<Double>/Array<Boolean>/... reads
        // a boxed pointer as if it were a raw primitive and corrupts the slot with a
        // raw value, breaking every later boxed-aware read of that element.
        let compoundReceiverIsGenericArray = isGenericArrayReceiverType(receiverBoundType, sema: sema, interner: interner)
        let boxingTable = BoxingCalleeTable(interner: interner)
        // Prefer the receiver's own type argument (Array<T>'s T) over the RHS
        // value's type: the RHS may be a narrower type that gets implicitly
        // widened (e.g. an Int literal assigned into an Array<Long> slot), and
        // boxing/unboxing must use the slot's actual element type, not the
        // operand's.
        let compoundPrimitiveElementType: TypeID? = compoundReceiverIsGenericArray
            ? (genericArrayElementType(of: receiverBoundType, sema: sema) ?? sema.bindings.exprTypes[valueExpr])
            : nil

        let rawGetResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: rawGetResult,
            canThrow: false,
            thrownResult: nil
        ))
        let getResult: KIRExprID
        if let elementType = compoundPrimitiveElementType,
           let unboxCallee = boxingTable.unboxCallee(for: elementType, types: sema.types, requireNonNull: true)
        {
            getResult = emitNonThrowingCall(
                callee: unboxCallee,
                arg: rawGetResult,
                resultType: elementType,
                arena: arena,
                into: &instructions
            )
        } else {
            getResult = rawGetResult
        }
        // Kotlin evaluates `a[i] += v` as receiver, index, get, value, op, set.
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        if let elementOperator {
            guard let newElement = emitIndexedElementOperatorCall(
                elementOperator,
                element: getResult,
                valueID: valueID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            ) else {
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [receiverID, indexID, newElement],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        let opResult = arena.appendTemporary(type: sema.types.anyType)
        // Determine the runtime op stub.
        // Use __kk_string_concat_flat for String += String (matching lowerBinaryExpr pattern),
        // otherwise use the appropriate numeric op stub.
        // Note: exprID's bound type is always unitType for compound assign, so we
        // derive the element type from the receiver's array type instead.
        let stringType = sema.types.stringType
        let receiverElementType = receiverBoundType.flatMap {
            TypeCheckHelpers().arrayElementType(for: $0, sema: sema, interner: interner)
        }
        let isStringElement = receiverElementType == stringType
        let isUnsignedElement = receiverElementType.map { sema.types.isUnsigned($0) } ?? false
        let floatingPointPrefix: String? = if let receiverElementType {
            switch sema.types.kind(of: receiverElementType) {
            case .primitive(.double, _): "d"
            case .primitive(.float, _): "f"
            default: nil
            }
        } else {
            nil
        }
        let opName = if op == .plusAssign, isStringElement {
            "__kk_string_concat_flat"
        } else if let floatingPointPrefix {
            // Compound assignment on Array<Double>/Array<Float> must use the
            // floating-point runtime ABI. The generic integer stubs reinterpret
            // the bit-encoded operands as signed integers and corrupt the result.
            switch op {
            case .plusAssign: "kk_op_\(floatingPointPrefix)add"
            case .minusAssign: "kk_op_\(floatingPointPrefix)sub"
            case .timesAssign: "kk_op_\(floatingPointPrefix)mul"
            case .divAssign: "kk_op_\(floatingPointPrefix)div"
            case .modAssign: "kk_op_\(floatingPointPrefix)mod"
            }
        } else {
            switch op {
            case .plusAssign: "kk_op_add"
            case .minusAssign: "kk_op_sub"
            case .timesAssign: "kk_op_mul"
            case .divAssign: isUnsignedElement ? "kk_op_udiv" : "kk_op_div"
            case .modAssign: isUnsignedElement ? "kk_op_urem" : "kk_op_mod"
            }
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(opName),
            arguments: [getResult, valueID],
            result: opResult,
            canThrow: false,
            thrownResult: nil
        ))
        let storedOpResult: KIRExprID
        if let elementType = compoundPrimitiveElementType,
           let boxCallee = boxingTable.boxCallee(for: elementType, types: sema.types, requireNonNull: false)
        {
            storedOpResult = emitNonThrowingCall(
                callee: boxCallee,
                arg: opResult,
                resultType: sema.types.anyType,
                arena: arena,
                into: &instructions
            )
        } else {
            storedOpResult = opResult
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, storedOpResult],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// Lowers `a[i] op= v` / `a[i]++`/`a[i]--` through the custom (or
    /// source-backed member, e.g. MutableList) get()/set() pair resolved by
    /// LocalDeclTypeChecker+IndexedCompoundAssignAndLocalFunctions.swift's
    /// bindIndexedCompoundAssignSetOperator, instead of the raw array
    /// runtime used by the fallback path in lowerIndexedCompoundAssignExpr:
    ///   1) t = receiver.get(i...)
    ///   2) t' = kk_op_*(t, v), or the element's own operator
    ///      (`t.plus(v)`, `t.inc()`; an in-place `t.plusAssign(v)` stops here)
    ///   3) receiver.set(i..., t')
    /// emitMemberCallInstruction derives each call's own throwing ABI from
    /// its resolved callee, so a throwing custom get()/set() propagates
    /// correctly without special-casing here.
    private func lowerIndexedCompoundAssignExprViaCustomOperator(
        _ exprID: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        receiverID: KIRExprID,
        getCallBinding: CallBinding,
        operatorBinding: IndexedCompoundAssignOperatorBinding?,
        elementOperator: IndexedCompoundAssignElementOperatorBinding?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let loweredIndices = indices.map { indexExpr in
            let rawIndex = driver.lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            return needsEvaluationOrderFreeze(indexExpr, ast: ast, sema: sema)
                && expressionMayMutateState(valueExpr, ast: ast)
                ? freezeEvaluationOrderOperand(rawIndex, arena: arena, instructions: &instructions)
                : rawIndex
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        guard let elementType = operatorBinding?.elementType ?? elementOperator?.elementType else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }

        let getResult = arena.appendTemporary(type: elementType)
        emitMemberCallInstruction(
            normalized: driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredIndices,
                callBinding: getCallBinding,
                chosenCallee: getCallBinding.chosenCallee,
                spreadFlags: Array(repeating: false, count: loweredIndices.count),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            ),
            callBinding: getCallBinding,
            chosenCallee: getCallBinding.chosenCallee,
            calleeName: interner.intern("get"),
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
            result: getResult,
            isSuperCall: isSuperCall,
            qualifiedSuperType: nil,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: [receiverID] + loweredIndices
        )

        // Kotlin evaluates `b[i] += v` as receiver, indices, get, value, op, set.
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let newElement: KIRExprID
        if let elementOperator {
            guard let operatorResult = emitIndexedElementOperatorCall(
                elementOperator,
                element: getResult,
                valueID: valueID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            ) else {
                // In-place `plusAssign`: no set() write-back.
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            newElement = operatorResult
        } else {
            newElement = emitBuiltinIndexedCompoundOp(
                op: op, elementType: elementType, current: getResult, valueID: valueID,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }

        guard let operatorBinding else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        let setCallBinding = operatorBinding.setCall
        let setArguments = loweredIndices + [newElement]
        let setResult = arena.appendTemporary(type: sema.types.unitType)
        emitMemberCallInstruction(
            normalized: driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: setArguments,
                callBinding: setCallBinding,
                chosenCallee: setCallBinding.chosenCallee,
                spreadFlags: Array(repeating: false, count: setArguments.count),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            ),
            callBinding: setCallBinding,
            chosenCallee: setCallBinding.chosenCallee,
            calleeName: interner.intern("set"),
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
            result: setResult,
            isSuperCall: isSuperCall,
            qualifiedSuperType: nil,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: [receiverID] + setArguments
        )

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// Builtin numeric/String arithmetic for `get() op v` on a custom get/set
    /// receiver whose element type defines no operator of its own.
    private func emitBuiltinIndexedCompoundOp(
        op: CompoundAssignOp,
        elementType: TypeID,
        current getResult: KIRExprID,
        valueID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Determine the runtime op stub from the get() result's own element
        // type — mirroring the raw-array path below, but keyed off the
        // custom operator's actual return type rather than the receiver's
        // array element type (the receiver here isn't array-shaped).
        let stringType = sema.types.stringType
        let isStringElement = elementType == stringType
        let isUnsignedElement = sema.types.isUnsigned(elementType)
        let floatingPointPrefix: String? = switch sema.types.kind(of: elementType) {
        case .primitive(.double, _): "d"
        case .primitive(.float, _): "f"
        default: nil
        }
        let opName = if op == .plusAssign, isStringElement {
            "__kk_string_concat_flat"
        } else if let floatingPointPrefix {
            switch op {
            case .plusAssign: "kk_op_\(floatingPointPrefix)add"
            case .minusAssign: "kk_op_\(floatingPointPrefix)sub"
            case .timesAssign: "kk_op_\(floatingPointPrefix)mul"
            case .divAssign: "kk_op_\(floatingPointPrefix)div"
            case .modAssign: "kk_op_\(floatingPointPrefix)mod"
            }
        } else {
            switch op {
            case .plusAssign: "kk_op_add"
            case .minusAssign: "kk_op_sub"
            case .timesAssign: "kk_op_mul"
            case .divAssign: isUnsignedElement ? "kk_op_udiv" : "kk_op_div"
            case .modAssign: isUnsignedElement ? "kk_op_urem" : "kk_op_mod"
            }
        }
        let opResult = arena.appendTemporary(type: elementType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(opName),
            arguments: [getResult, valueID],
            result: opResult,
            canThrow: false,
            thrownResult: nil
        ))

        return opResult
    }

    /// Calls the element type's own operator resolved by Sema for
    /// `a[i] op= v` / `a[i]++` on the `get()` result. Mirrors the direct-call
    /// pattern of lowerMemberCompoundAssignExpr: the element has no AST
    /// receiver expression, so emitMemberCallInstruction does not apply.
    /// Returns nil for an in-place `plusAssign`, which leaves nothing to store.
    private func emitIndexedElementOperatorCall(
        _ binding: IndexedCompoundAssignElementOperatorBinding,
        element: KIRExprID,
        valueID: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let callee = binding.call.chosenCallee
        var arguments = [element]
        if binding.kind != .incrementDecrement {
            let normalized = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: [valueID],
                callBinding: binding.call,
                chosenCallee: callee,
                spreadFlags: [false],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            arguments.append(contentsOf: normalized.arguments)
        }
        let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callee),
                                                   !externalLinkName.isEmpty
        {
            interner.intern(externalLinkName)
        } else {
            sema.symbols.symbol(callee)?.name ?? interner.intern("plus")
        }
        let callResult = arena.appendTemporary(type: binding.resultType)
        instructions.append(.call(
            symbol: callee,
            callee: loweredCalleeName,
            arguments: arguments,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        return binding.kind == .inPlace ? nil : callResult
    }

    /// Extracts `T` from a `classType`'s first (invariant/out/in) type
    /// argument, e.g. `Array<T>` or `MutableList<T>`. Returns nil for a star
    /// projection or a non-generic/non-class receiver type.
    func genericArrayElementType(of receiverType: TypeID?, sema: SemaModule) -> TypeID? {
        guard let receiverType,
              case let .classType(classType) = sema.types.kind(of: receiverType),
              let firstArg = classType.args.first
        else {
            return nil
        }
        switch firstArg {
        case let .invariant(t), let .out(t), let .in(t): return t
        case .star: return nil
        }
    }
}
