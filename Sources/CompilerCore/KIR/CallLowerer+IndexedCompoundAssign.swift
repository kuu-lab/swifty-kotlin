
extension CallLowerer {

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
        let receiverElementType = receiverBoundType.flatMap {
            TypeCheckHelpers().arrayElementType(for: $0, sema: sema, interner: interner)
        }
        let compoundPrimitiveElementType: TypeID? = compoundReceiverIsGenericArray
            ? (genericArrayElementType(of: receiverBoundType, sema: sema) ?? sema.bindings.exprTypes[valueExpr])
            : nil

        let rawGetResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: rawGetResult,
            canThrow: false
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
        let valueID: KIRExprID
        if ast.arena.isIncrementDecrement(exprID), elementOperator == nil,
           let receiverElementType
        {
            let one: KIRExprKind?
            switch sema.types.kind(of: receiverElementType) {
            case .primitive(.float, .nonNull): one = .floatLiteral(1.0)
            case .primitive(.double, .nonNull): one = .doubleLiteral(1.0)
            default: one = nil
            }
            if let one {
                valueID = arena.appendExpr(one, type: receiverElementType)
                instructions.append(.constValue(result: valueID, value: one))
            } else {
                valueID = driver.lowerExpr(
                    valueExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
        } else {
            valueID = driver.lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        if let elementOperator {
            guard let newElement = emitIndexedElementOperatorCall(
                elementOperator,
                element: getResult,
                valueID: valueID,
                callExprID: exprID,
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
                callee: interner.intern("kk_array_set"),
                arguments: [receiverID, indexID, newElement],
                result: nil,
                canThrow: false
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        let opResult: KIRExprID
        if op == .plusAssign, let elementType = receiverElementType,
           sema.types.makeNonNullable(elementType) == sema.types.stringType {
            // The flat concat ABI requires two strings, including a nullable
            // current element and an arbitrary RHS accepted by String.plus.
            opResult = emitBuiltinIndexedCompoundOp(
                op: op, elementType: elementType, current: getResult,
                valueID: valueID, valueType: sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        } else {
            // Preserve the array element type on the arithmetic result so
            // IntegerNarrowingPass can apply Int/UInt/Char overflow semantics.
            let operationResultType = compoundPrimitiveElementType ?? receiverElementType ?? sema.types.anyType
            opResult = arena.appendTemporary(type: operationResultType)
            // exprID's bound type is always unitType for compound assign, so we
            // derive the element type from the receiver's array type instead.
            let stringType = sema.types.stringType
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
                callee: interner.intern(opName),
                arguments: [getResult, valueID],
                result: opResult,
                canThrow: false
            ))
        }
        let elementTypeForWriteBack = compoundPrimitiveElementType ?? receiverElementType
        let wrappedOpResult: KIRExprID
        if let elementTypeForWriteBack,
           let wrapped = SmallIntegerWrap.append(
               opResult,
               type: elementTypeForWriteBack,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            wrappedOpResult = wrapped
        } else {
            wrappedOpResult = opResult
        }
        let storedOpResult: KIRExprID
        if let elementType = compoundPrimitiveElementType,
           let boxCallee = boxingTable.boxCallee(for: elementType, types: sema.types, requireNonNull: false)
        {
            storedOpResult = emitNonThrowingCall(
                callee: boxCallee,
                arg: wrappedOpResult,
                resultType: sema.types.anyType,
                arena: arena,
                into: &instructions
            )
        } else {
            storedOpResult = wrappedOpResult
        }
        instructions.append(.call(
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, storedOpResult],
            result: nil,
            canThrow: false
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

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
        var loweredIndices: [KIRExprID] = []
        for (position, indexExpr) in indices.enumerated() {
            let rawIndex = driver.lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let laterOperands = indices.dropFirst(position + 1) + [valueExpr]
            let shouldFreeze = needsEvaluationOrderFreeze(indexExpr, ast: ast, sema: sema)
                && anyExpressionMayMutateState(laterOperands, ast: ast)
            loweredIndices.append(shouldFreeze
                ? freezeEvaluationOrderOperand(rawIndex, arena: arena, instructions: &instructions)
                : rawIndex)
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        guard let elementType = operatorBinding?.elementType ?? elementOperator?.elementType else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }

        let getResult = arena.appendTemporary(type: elementType)
        let normalizedGetArguments = driver.callSupportLowerer.normalizedCallArguments(
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
        )
        emitMemberCallInstruction(
            normalized: normalizedGetArguments,
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
            arguments: [receiverID] + normalizedGetArguments.arguments
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
                callExprID: exprID,
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
                valueType: sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType,
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
        let normalizedSetArguments = driver.callSupportLowerer.normalizedCallArguments(
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
        )
        let setResult = arena.appendTemporary(type: sema.types.unitType)
        emitMemberCallInstruction(
            normalized: normalizedSetArguments,
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
            arguments: [receiverID] + normalizedSetArguments.arguments
        )

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    private func emitBuiltinIndexedCompoundOp(
        op: CompoundAssignOp,
        elementType: TypeID,
        current getResult: KIRExprID,
        valueID: KIRExprID,
        valueType: TypeID,
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
        let nullableStringType = sema.types.makeNullable(stringType)
        if op == .plusAssign,
           elementType == stringType || elementType == nullableStringType
        {
            let stringCurrent = elementType == stringType
                ? getResult
                : emitAnyToStringWithNullGuard(
                    valueID: getResult,
                    valueType: elementType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            let stringValue = valueType == stringType
                ? valueID
                : emitAnyToStringWithNullGuard(
                    valueID: valueID,
                    valueType: valueType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            let result = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                callee: interner.intern("__kk_string_concat_flat"),
                arguments: [stringCurrent, stringValue],
                result: result,
                canThrow: false
            ))
            return result
        }
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
        let effectiveValueID: KIRExprID
        if let floatingPointPrefix {
            let rhsIsFloatingPoint: Bool = switch sema.types.kind(of: valueType) {
            case .primitive(.float, _), .primitive(.double, _): true
            default: false
            }
            effectiveValueID = widenIntegerOperandToFloatingPoint(
                valueID,
                operandTypeID: valueType,
                isFloatingPoint: rhsIsFloatingPoint,
                toDouble: floatingPointPrefix == "d",
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        } else {
            effectiveValueID = valueID
        }
        let opResult = arena.appendTemporary(type: elementType)
        instructions.append(.call(
            callee: interner.intern(opName),
            arguments: [getResult, effectiveValueID],
            result: opResult,
            canThrow: false
        ))
        return SmallIntegerWrap.append(
            opResult,
            type: elementType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) ?? opResult
    }

    /// Mirrors the direct-call pattern of lowerMemberCompoundAssignExpr: the
    /// element has no AST receiver expression, so emitMemberCallInstruction
    /// does not apply. Returns nil for an in-place `plusAssign`, which leaves
    /// nothing to store.
    private func emitIndexedElementOperatorCall(
        _ binding: IndexedCompoundAssignElementOperatorBinding,
        element: KIRExprID,
        valueID: KIRExprID,
        callExprID: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let callee = binding.call.chosenCallee
        if binding.kind == .incrementDecrement {
            // `++`/`--` invoke `inc()`/`dec()` with no explicit arguments, so
            // defaulted parameters must ride the `<name>$default` stub just
            // like an explicit `a.inc()` call.
            let callResult = arena.appendTemporary(type: binding.resultType)
            emitIncrementDecrementOperatorCall(
                callBinding: binding.call,
                operatorName: sema.symbols.symbol(callee)
                    .map { interner.resolve($0.name) } ?? "inc",
                receiverArgument: element,
                callExprID: callExprID,
                result: callResult,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            return callResult
        }
        var arguments = [element]
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
            canThrow: false
        ))
        return binding.kind == .inPlace ? nil : callResult
    }

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
