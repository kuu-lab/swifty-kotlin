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
        let floatingPointCallee = floatingPointRangeContainsCallee(
            for: rhsExpr, value: lhsExpr, sema: sema, interner: interner
        )

        if !negated {
            let result = arena.appendTemporary(type: boundType ?? boolType)
            if let floatingPointCallee {
                let floatingPointValueID = floatingPointRangeContainsValueID(
                    lhsID, valueExpr: lhsExpr, callee: floatingPointCallee,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: floatingPointCallee,
                    arguments: [rhsID, floatingPointValueID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
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

        let notInContainsCallee: String = if let floatingPointCallee {
            interner.resolve(floatingPointCallee)
        } else {
            "kk_op_contains"
        }
        let containsResult = arena.appendTemporary(type: boolType)
        if notInContainsCallee.hasPrefix("__kk_") {
            let floatingPointValueID: KIRExprID = if let floatingPointCallee {
                floatingPointRangeContainsValueID(
                    lhsID, valueExpr: lhsExpr, callee: floatingPointCallee,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            } else {
                lhsID
            }
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(notInContainsCallee),
                arguments: [rhsID, floatingPointValueID],
                result: containsResult,
                canThrow: false,
                thrownResult: nil
            ))
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
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_contains"),
                arguments: [containerID, elementID],
                result: resultID,
                canThrow: false,
                thrownResult: nil
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

    private func floatingPointRangeContainsCallee(
        for rangeExpr: ExprID,
        value valueExpr: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let elementType = sema.bindings.floatingPointRangeElementType(forExpr: rangeExpr)
            ?? sema.bindings.identifierSymbol(for: rangeExpr).flatMap {
                sema.bindings.floatingPointRangeElementType(forSymbol: $0)
        }
        guard let elementType else { return nil }
        let valueType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType
        )
        if elementType == sema.types.floatType {
            guard valueType == sema.types.floatType else { return nil }
            return interner.intern("__kk_float_range_contains")
        }
        if elementType == sema.types.doubleType {
            guard valueType == sema.types.doubleType || valueType == sema.types.floatType else { return nil }
            return interner.intern("__kk_double_range_contains")
        }
        return nil
    }

    private func floatingPointRangeContainsValueID(
        _ valueID: KIRExprID,
        valueExpr: ExprID,
        callee: InternedString,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard callee == interner.intern("__kk_double_range_contains"),
              sema.types.makeNonNullable(sema.bindings.exprTypes[valueExpr] ?? sema.types.anyType)
                  == sema.types.floatType
        else {
            return valueID
        }
        let converted = arena.appendTemporary(type: sema.types.doubleType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_float_to_double_bits"),
            arguments: [valueID],
            result: converted,
            canThrow: false,
            thrownResult: nil
        ))
        return converted
    }

}
