
/// Lowering for member assignment expressions.
extension CallLowerer {
    // MARK: - Member Assignment

    func lowerMemberAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
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
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Synthetic properties whose getter external link ends in `_load`
        // (e.g. AtomicBoolean.value → kk_atomic_bool_load) must route their
        // setter to the matching `_store` runtime function rather than a
        // direct field-offset write, which would corrupt the underlying
        // runtime-managed box.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let info = sema.symbols.symbol(propertySymbol),
           info.flags.contains(.synthetic),
           let getterLink = sema.symbols.externalLinkName(for: propertySymbol),
           getterLink.hasSuffix("_load")
        {
            let storeLinkName = String(getterLink.dropLast("_load".count)) + "_store"
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(storeLinkName),
                arguments: [receiverID, valueID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface
           || ownerInfo.kind == .object,
           memberPropertyHasCustomSetterBody(propertySymbol, ast: ast, sema: sema)
        {
            // Must call the setter (not write the backing field directly) so its
            // body actually runs. Dispatched directly via the synthetic accessor
            // symbol scheme — the same reliable mechanism the read side already
            // uses for custom getters — rather than the chosenCallee-based
            // fallback below, which resolves plain stored-property assignment
            // and is not set up to name this accessor correctly.
            let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
            let result = arena.appendTemporary(type: sema.types.unitType)
            instructions.append(.call(
                symbol: setterSymbol,
                callee: interner.intern("set"),
                arguments: [receiverID, valueID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface
           || ownerInfo.kind == .object,
           let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
               sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
           ]
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [receiverID, offsetExpr, valueID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Use the call binding from sema if available (property setter).
        let callBinding = sema.bindings.callBindings[exprID]
        let chosenCallee = callBinding?.chosenCallee
        let setterName = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiverExpr,
            argumentCount: 2, // receiver + value
            sema: sema,
            interner: interner
        )
        let result = arena.appendTemporary(type: sema.types.unitType)
        instructions.append(.call(
            symbol: chosenCallee,
            callee: setterName,
            arguments: [receiverID, valueID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    // MARK: - Member Compound Assignment

    /// Lowers `receiver.field op= value` (and the desugared form of
    /// `receiver.field++` / `receiver.field--`) as load -> compute -> store,
    /// evaluating `receiver` exactly once. A custom getter/setter body must be
    /// called (not bypassed by reading/writing the backing field directly) so
    /// its logic actually runs on each side independently — e.g. a
    /// clamping `set(v) { field = v.coerceIn(0, 100) }` with a default
    /// getter still needs the load side to read the plain field but the
    /// store side to go through the setter. Absent a custom accessor on a
    /// given side, load/store fall back to `lowerMemberAssignExpr`'s other
    /// two safe, well-defined storage strategies — a synthetic runtime
    /// accessor (`_load`/`_store` link-name pair) or a direct field offset —
    /// or, for anything else (e.g. a delegated property's setter), the same
    /// best-effort setter/getter name fallback that plain member assignment
    /// already relies on.
    func lowerMemberCompoundAssignExpr(
        _ exprID: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        calleeName: InternedString,
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
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let propertySymbol = sema.bindings.identifierSymbol(for: exprID)
        let propType = propertySymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.bindings.exprTypes[exprID]
            ?? sema.types.anyType

        let ownerIsNominal: Bool = {
            guard let propertySymbol,
                  let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
                  let ownerInfo = sema.symbols.symbol(ownerSymbol)
            else {
                return false
            }
            return ownerInfo.kind == .class || ownerInfo.kind == .interface || ownerInfo.kind == .object
        }()
        // Mirrors the read side's tryLowerMemberPropertyAccessorRead / the
        // setter branch lowerMemberAssignExpr added for plain assignment —
        // both must be checked independently of each other and of the
        // field-offset/synthetic-link strategies below.
        let usesCustomGetter = ownerIsNominal
            && (propertySymbol.map { memberPropertyUsesAccessor($0, ast: ast, sema: sema) } ?? false)
        let usesCustomSetter = ownerIsNominal
            && (propertySymbol.map { memberPropertyHasCustomSetterBody($0, ast: ast, sema: sema) } ?? false)

        // Synthetic runtime accessor (e.g. AtomicBoolean.value -> kk_atomic_bool_load/_store).
        let syntheticLinks: (load: String, store: String)? = {
            guard let propertySymbol,
                  let info = sema.symbols.symbol(propertySymbol),
                  info.flags.contains(.synthetic),
                  let getterLink = sema.symbols.externalLinkName(for: propertySymbol),
                  getterLink.hasSuffix("_load")
            else {
                return nil
            }
            return (getterLink, String(getterLink.dropLast("_load".count)) + "_store")
        }()

        // Direct field-offset storage for ordinary stored properties.
        let fieldOffset: Int? = {
            guard syntheticLinks == nil,
                  let propertySymbol,
                  let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
                  let ownerInfo = sema.symbols.symbol(ownerSymbol),
                  ownerInfo.kind == .class || ownerInfo.kind == .interface || ownerInfo.kind == .object
            else {
                return nil
            }
            return sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            ]
        }()

        // ── Load ─────────────────────────────────────────────────────────
        let currentValue: KIRExprID
        if usesCustomGetter, let propertySymbol {
            let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
            let result = arena.appendTemporary(type: propType)
            instructions.append(.call(
                symbol: getterSymbol,
                callee: interner.intern("get"),
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            currentValue = result
        } else if let syntheticLinks {
            let result = arena.appendTemporary(type: propType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(syntheticLinks.load),
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            currentValue = result
        } else if let fieldOffset {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let result = arena.appendTemporary(type: propType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverID, offsetExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            currentValue = propertySymbol.map {
                wrapLateinitReadIfNeeded(
                    result, symbol: $0, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                )
            } ?? result
        } else {
            let getterName = loweredMemberCalleeName(
                chosenCallee: nil,
                fallback: calleeName,
                receiverExpr: receiverExpr,
                argumentCount: 1,
                sema: sema,
                interner: interner
            )
            let result = arena.appendTemporary(type: propType)
            instructions.append(.call(
                symbol: nil,
                callee: getterName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            currentValue = result
        }

        // ── Compute ──────────────────────────────────────────────────────
        // `newValue == nil` means a Unit-returning `plusAssign`-style operator
        // already mutated the loaded value in place, so no store is needed —
        // mirrors bare-name compound assign's handling in ExprLowerer.
        let newValue: KIRExprID? = {
            if let callBinding = sema.bindings.callBindings[exprID],
               let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
               signature.receiverType != nil
            {
                let normalized = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: [valueID],
                    callBinding: callBinding,
                    chosenCallee: callBinding.chosenCallee,
                    spreadFlags: [false],
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                var finalArguments = normalized.arguments
                finalArguments.insert(currentValue, at: 0)
                let returnType = signature.returnType
                let callResult = arena.appendTemporary(type: returnType)
                let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                            !externalLinkName.isEmpty
                {
                    interner.intern(externalLinkName)
                } else {
                    sema.symbols.symbol(callBinding.chosenCallee)?.name ?? interner.intern(op.kotlinFunctionName)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                return returnType == sema.types.unitType ? nil : callResult
            }

            // Builtin path: Int/Long/Double/... arithmetic or String
            // concatenation, matching bare-name compound assign's fallback.
            let kirOp: KIRBinaryOp = switch op {
            case .plusAssign: .add
            case .minusAssign: .subtract
            case .timesAssign: .multiply
            case .divAssign: .divide
            case .modAssign: .modulo
            }
            let stringType = sema.types.stringType
            let nullableStringType = sema.types.makeNullable(stringType)
            let valueType = arena.exprType(valueID)
            let isStringCompound = op == .plusAssign
                && (propType == stringType || propType == nullableStringType
                    || valueType == stringType || valueType == nullableStringType)
            if !isStringCompound {
                let result = arena.appendTemporary(type: propType)
                instructions.append(.binary(op: kirOp, lhs: currentValue, rhs: valueID, result: result))
                return result
            }
            let result = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_concat_flat"),
                arguments: [currentValue, valueID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }()

        // ── Store ────────────────────────────────────────────────────────
        if let newValue {
            if usesCustomSetter, let propertySymbol {
                let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                    ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
                let setterResult = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.call(
                    symbol: setterSymbol,
                    callee: interner.intern("set"),
                    arguments: [receiverID, newValue],
                    result: setterResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if let syntheticLinks {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(syntheticLinks.store),
                    arguments: [receiverID, newValue],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if let fieldOffset {
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [receiverID, offsetExpr, newValue],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let setterName = loweredMemberCalleeName(
                    chosenCallee: nil,
                    fallback: calleeName,
                    receiverExpr: receiverExpr,
                    argumentCount: 2,
                    sema: sema,
                    interner: interner
                )
                let setterResult = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.call(
                    symbol: nil,
                    callee: setterName,
                    arguments: [receiverID, newValue],
                    result: setterResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
