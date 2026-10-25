extension ExprLowerer {
    /// `when` branch conditions (`ControlFlowLowerer+WhenExpr.swift`) reuse the
    /// subject's single lowering here instead of re-lowering `lhsExpr`, which
    /// would re-evaluate a side-effecting subject once per `in`/`!in` branch.
    func lowerContainsCheck(
        exprID: ExprID,
        lhsID: KIRExprID,
        lhsExpr: ExprID,
        rhsExpr: ExprID,
        negated: Bool,
        boundType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let rhsID = lowerExpr(
            rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
        )
        // KSP-1523: UInt used to get its own branch here (`kk_uint_range_contains`),
        // gated on `rhsType == uintType` — but `rhsType` is the range's own type
        // (e.g. UIntRange), never its element type, so that comparison was always
        // false. UInt now falls through to the same `appendContainsCall` path as
        // every other range, which resolves to the shared `__kk_range_contains`
        // bridge (safe: UInt always fits the Int64 fields it operates on).
        let floatingPointPlan = floatingPointRangeContainsPlan(
            for: rhsExpr, value: lhsExpr, sema: sema, ast: ast, interner: interner
        )

        if !negated {
            let result = arena.appendTemporary(type: boundType ?? boolType)
            if let floatingPointPlan {
                emitFloatingPointRangeContains(
                    floatingPointPlan, rangeID: rhsID, valueID: lhsID,
                    valueExpr: lhsExpr, resultID: result, sema: sema,
                    arena: arena, interner: interner, instructions: &instructions
                )
            } else {
                appendContainsCall(
                    exprID: exprID,
                    elementID: lhsID,
                    containerID: rhsID,
                    containerExpr: rhsExpr,
                    resultID: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            return result
        }

        let containsResult = arena.appendTemporary(type: boolType)
        if let floatingPointPlan {
            emitFloatingPointRangeContains(
                floatingPointPlan, rangeID: rhsID, valueID: lhsID,
                valueExpr: lhsExpr, resultID: containsResult, sema: sema,
                arena: arena, interner: interner, instructions: &instructions
            )
        } else {
            appendContainsCall(
                exprID: exprID,
                elementID: lhsID,
                containerID: rhsID,
                containerExpr: rhsExpr,
                resultID: containsResult,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        let result = arena.appendTemporary(type: boundType ?? boolType)
        let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
        instructions.append(.binary(op: .equal, lhs: containsResult, rhs: falseValue, result: result))
        return result
    }

    private func appendContainsCall(
        exprID: ExprID,
        elementID: KIRExprID,
        containerID: KIRExprID,
        containerExpr: ExprID,
        resultID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        if
           let callBinding = sema.bindings.callBindings[exprID],
           callBinding.chosenCallee != .invalid,
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil
              || isRangeObjectReceiver(containerExpr, sema: sema, interner: interner)
        {
            let calleeName: InternedString
            // Set when `calleeName` is a concrete runtime range bridge rather
            // than the member itself; such callees must never be dispatched
            // through a vtable/itable (mirrors the remap gate in
            // `CallLowerer+MemberCallEmission`).
            var remappedToRangeBridge = false
            if let linkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
               !linkName.isEmpty
            {
                calleeName = interner.intern(linkName)
            } else if let receiverType = sema.bindings.exprTypes[containerExpr],
                      let rangeLink = driver.callLowerer.closedRangeInterfaceRuntimeName(
                          memberName: "contains",
                          receiverExpr: containerExpr,
                          receiverType: receiverType,
                          chosenCallee: callBinding.chosenCallee,
                          sema: sema,
                          interner: interner
                      )
            {
                // Generic range interface members may lack a link name; use
                // the concrete runtime bridge, as in the `r.contains(x)` path.
                calleeName = rangeLink
                remappedToRangeBridge = true
            } else if let sym = sema.symbols.symbol(callBinding.chosenCallee) {
                calleeName = sym.name
            } else {
                calleeName = interner.intern("contains")
            }
            // An open member `contains` must dispatch on the container's
            // runtime type, exactly like `container.contains(element)`.
            // A virtual call supplies the receiver through its own field, so
            // a nominal member (receiverType == nil) only passes the value
            // argument; an extension callee still carries its receiver as
            // argument 0, which tryEmitVirtualDispatch drops.
            let virtualArguments: [KIRExprID] = signature.receiverType == nil
                ? [elementID]
                : [containerID, elementID]
            if !remappedToRangeBridge,
               let virtualInstruction = driver.callLowerer.tryEmitVirtualDispatch(
                   chosenCallee: callBinding.chosenCallee,
                   calleeName: calleeName,
                   receiverExpr: containerExpr,
                   loweredReceiverID: containerID,
                   isSuperCall: false,
                   finalArguments: virtualArguments,
                   result: resultID,
                   sema: sema,
                   arena: arena,
                   interner: interner
               )
            {
                // KUU-763: an interface-typed `ClosedRange`/`ClosedFloatingPointRange`
                // receiver holding a floating-point range box has no itable —
                // probe the runtime representation before dispatching.
                if let probeEndLabel = driver.callLowerer.emitFloatingPointRangeMemberProbe(
                    chosenCallee: callBinding.chosenCallee,
                    receiverID: containerID,
                    arguments: [containerID, elementID],
                    result: resultID,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) {
                    instructions.append(virtualInstruction)
                    instructions.append(.label(probeEndLabel))
                } else {
                    instructions.append(virtualInstruction)
                }
                return
            }
            instructions.append(.call(
                symbol: callBinding.chosenCallee,
                callee: calleeName,
                arguments: [containerID, elementID],
                result: resultID,
                canThrow: false
            ))
        } else {
            instructions.append(.call(
                callee: interner.intern("kk_op_contains"),
                arguments: [containerID, elementID],
                result: resultID,
                canThrow: false
            ))
        }
    }

    /// `kk_op_contains` only recognizes runtime range boxes, collections and
    /// arrays — a heap object such as a `ComparableRange` or a user-defined
    /// `ClosedRange` implementation falls through and silently yields false.
    /// When the container's static type conforms to `ClosedRange` or
    /// `OpenEndRange`, a member `contains` callee (signature.receiverType ==
    /// nil) must dispatch through the resolved callee: the runtime-range
    /// bridge remap still covers tracked boxes, while source objects go
    /// through interface dispatch (KUU-2941).
    private func isRangeObjectReceiver(
        _ containerExpr: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let containerType = sema.bindings.exprTypes[containerExpr],
              let (containerClass, _) = resolveClassTypeSymbol(
                  sema.types.makeNonNullable(containerType), sema: sema
              )
        else {
            return false
        }
        for name in ["ClosedRange", "OpenEndRange"] {
            if let rangeSymbol = sema.symbols.lookup(
                fqName: ["kotlin", "ranges", name].map(interner.intern)
            ), sema.types.isNominalSubtypeSymbol(containerClass.classSymbol, of: rangeSymbol) {
                return true
            }
        }
        return false
    }

    /// How `x in <floating-point range>` must reach the box so the answer
    /// matches kotlinc/JVM for cross-type operands (KUU-3228).
    private enum FloatingPointRangeContainsPlan {
        /// `x in a..b` / `x in a..<b` on a Float range with a Double operand.
        /// The JVM `in` intrinsic compares the promoted bounds
        /// (`a.toDouble() <= x && x <= b.toDouble()`), so the operand keeps its
        /// full Double precision at the boundary — a `value.toFloat()`
        /// membership check rounds edge Doubles onto the bound and disagrees.
        case promoteFloatBounds(endExclusive: Bool)
        /// Any other container expression resolves the
        /// `ClosedRange<Float>.contains(Double)` (`floatRangeContains`)
        /// extension semantics on JVM: `contains(value.toFloat())`.
        case truncateValueToFloat
        /// `__kk_float_range_contains` with the Float operand passed through.
        case floatDirect
        /// `__kk_double_range_contains`; a Float operand is widened first.
        case doubleDirect
    }

    private func floatingPointRangeContainsPlan(
        for rangeExpr: ExprID,
        value valueExpr: ExprID,
        sema: SemaModule,
        ast: ASTModule,
        interner: StringInterner
    ) -> FloatingPointRangeContainsPlan? {
        let elementType = sema.bindings.floatingPointRangeElementType(forExpr: rangeExpr)
            ?? sema.bindings.identifierSymbol(for: rangeExpr).flatMap {
                sema.bindings.floatingPointRangeElementType(forSymbol: $0)
        }
        guard let elementType else { return nil }
        let valueType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType
        )
        if elementType == sema.types.floatType {
            if valueType == sema.types.floatType {
                return .floatDirect
            }
            guard valueType == sema.types.doubleType else { return nil }
            if case let .binary(op, _, _, _) = ast.arena.expr(rangeExpr),
               op == .rangeTo || op == .rangeUntil
            {
                return .promoteFloatBounds(endExclusive: op == .rangeUntil)
            }
            return .truncateValueToFloat
        }
        if elementType == sema.types.doubleType {
            guard valueType == sema.types.doubleType || valueType == sema.types.floatType else { return nil }
            return .doubleDirect
        }
        return nil
    }

    private func emitFloatingPointRangeContains(
        _ plan: FloatingPointRangeContainsPlan,
        rangeID: KIRExprID,
        valueID: KIRExprID,
        valueExpr: ExprID,
        resultID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        func call(_ callee: String, _ arguments: [KIRExprID], _ result: KIRExprID) {
            instructions.append(.call(callee: interner.intern(callee), arguments: arguments, result: result, canThrow: false))
        }
        func convert(_ callee: String, _ operand: KIRExprID, _ type: TypeID) -> KIRExprID {
            let converted = arena.appendTemporary(type: type)
            call(callee, [operand], converted)
            return converted
        }
        switch plan {
        case .floatDirect:
            call("__kk_float_range_contains", [rangeID, valueID], resultID)
        case .truncateValueToFloat:
            let floatValue = convert("kk_double_to_float", valueID, sema.types.floatType)
            call("__kk_float_range_contains", [rangeID, floatValue], resultID)
        case .doubleDirect:
            let valueType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType
            )
            let doubleValue: KIRExprID = if valueType == sema.types.floatType {
                convert("__kk_float_to_double_bits", valueID, sema.types.doubleType)
            } else {
                valueID
            }
            call("__kk_double_range_contains", [rangeID, doubleValue], resultID)
        case let .promoteFloatBounds(endExclusive):
            let boolType = sema.types.make(.primitive(.boolean, .nonNull))
            let floatType = sema.types.floatType
            let doubleType = sema.types.doubleType
            let startFloat = arena.appendTemporary(type: floatType)
            call("__kk_float_range_start", [rangeID], startFloat)
            let endFloat = arena.appendTemporary(type: floatType)
            call("__kk_float_range_endInclusive", [rangeID], endFloat)
            let start = convert("__kk_float_to_double_bits", startFloat, doubleType)
            let end = convert("__kk_float_to_double_bits", endFloat, doubleType)
            let aboveStart = arena.appendTemporary(type: boolType)
            instructions.append(.binary(op: .lessOrEqual, lhs: start, rhs: valueID, result: aboveStart))
            let belowEnd = arena.appendTemporary(type: boolType)
            instructions.append(.binary(
                op: endExclusive ? .lessThan : .lessOrEqual,
                lhs: valueID,
                rhs: end,
                result: belowEnd
            ))
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            instructions.append(.copy(from: falseValue, to: resultID))
            let endLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfEqual(lhs: aboveStart, rhs: falseValue, target: endLabel))
            instructions.append(.copy(from: belowEnd, to: resultID))
            instructions.append(.label(endLabel))
        }
    }

}
