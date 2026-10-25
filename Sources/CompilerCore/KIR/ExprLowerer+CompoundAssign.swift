extension ExprLowerer {
    func lowerCompoundAssign(
        op: CompoundAssignOp,
        valueExpr: ExprID,
        exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Kotlin's compound assignment reads the current target value
        // BEFORE evaluating the right-hand side (e.g. `y += y++ + ++y`
        // must read the pre-RHS value of `y`, not the value after the
        // RHS's own increments have run). Lowering the RHS eagerly here
        // — before any branch below has loaded the target's current
        // value — would append the RHS's (possibly side-effecting)
        // instructions first, so a later load of the same storage would
        // observe the mutated value. `lowerRHS()` is called exactly
        // once, from each branch below, immediately after that branch's
        // load of the current value.
        func lowerRHS() -> KIRExprID {
            lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let kirOp: KIRBinaryOp = switch op {
        case .plusAssign: .add
        case .minusAssign: .subtract
        case .timesAssign: .multiply
        case .divAssign: .divide
        case .modAssign: .modulo
        }
        let stringType = sema.types.stringType
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        var incrementDecrementResult: KIRExprID?

        func rememberIncrementDecrementResult(_ value: KIRExprID) {
            if ast.arena.incrementDecrementReturnsValue(exprID) {
                incrementDecrementResult = value
            }
        }

        func appendBuiltinCompoundResult(
            lhs: KIRExprID,
            lhsType: TypeID,
            rhs: KIRExprID,
            rhsType: TypeID?
        ) -> KIRExprID {
            let isStringCompound = op == .plusAssign
                && (
                    lhsType == stringType
                        || lhsType == nullableStringType
                        || rhsType == stringType
                        || rhsType == nullableStringType
                )
            if !isStringCompound {
                let resultType = arena.exprType(lhs) ?? lhsType
                let resultID = arena.appendTemporary(type: resultType)
                if op == .plusAssign,
                   driver.callLowerer.isCoroutineContextReceiverType(resultType, sema: sema, interner: interner)
                {
                    // Emit before try lowering, just like the context + path.
                    instructions.append(.call(
                        callee: interner.intern("__kk_context_plus_dispatch"),
                        arguments: [lhs, rhs],
                        result: resultID,
                        canThrow: true
                    ))
                } else {
                    instructions.append(.binary(op: kirOp, lhs: lhs, rhs: rhs, result: resultID))
                }
                // `b++` / `s--` / `ub++` on Byte, Short, UByte, UShort compute in a
                // 64-bit slot; wrap back to the operand's width (Kotlin `inc`/`dec`).
                if let wrapped = SmallIntegerWrap.append(
                    resultID, type: resultType, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                ) {
                    return wrapped
                }
                return resultID
            }

            let effectiveRHS: KIRExprID
            if rhsType == stringType {
                effectiveRHS = rhs
            } else {
                effectiveRHS = driver.callLowerer.emitAnyToStringWithNullGuard(
                    valueID: rhs,
                    valueType: rhsType ?? sema.types.anyType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }

            let effectiveLHS: KIRExprID
            if lhsType == stringType {
                effectiveLHS = lhs
            } else {
                effectiveLHS = driver.callLowerer.emitAnyToStringWithNullGuard(
                    valueID: lhs,
                    valueType: lhsType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }

            let resultID = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                callee: interner.intern("__kk_string_concat_flat"),
                arguments: [effectiveLHS, effectiveRHS],
                result: resultID,
                canThrow: false
            ))
            return resultID
        }

        func appendOperatorCompoundResult(
            lhs: KIRExprID,
            rhs: KIRExprID,
            resultType: TypeID
        ) -> KIRExprID? {
            // `String += Any?` can be bound to the source-backed
            // `String?.plus` extension during compound-assignment
            // resolution. That call does not carry the compiler's
            // Any-to-String conversion policy when used as the
            // read/modify/write operator, so route String receivers
            // through the builtin concatenation path below. Increment and
            // decrement instead dispatch through the selected `inc()` / `dec()`.
            let lhsType = arena.exprType(lhs) ?? sema.types.anyType
            if op == .plusAssign,
               !ast.arena.isIncrementDecrement(exprID),
               lhsType == stringType || lhsType == nullableStringType
            {
                return appendBuiltinCompoundResult(
                    lhs: lhs,
                    lhsType: lhsType,
                    rhs: rhs,
                    rhsType: arena.exprType(rhs)
                )
            }
            guard let callBinding = sema.bindings.callBindings[exprID],
                  let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
                  signature.receiverType != nil
            else {
                return nil
            }

            func appendOperatorCall(
                calleeName: InternedString,
                arguments: [KIRExprID],
                result: KIRExprID
            ) {
                let resolvedMemberName = sema.symbols.symbol(callBinding.chosenCallee)
                    .map { interner.resolve($0.name) }
                    ?? interner.resolve(calleeName)
                if driver.callLowerer.emitRuntimeBackedCollectionMemberCallIfNeeded(
                    memberName: resolvedMemberName,
                    receiverType: arena.exprType(lhs) ?? signature.receiverType ?? sema.types.anyType,
                    chosenCallee: callBinding.chosenCallee,
                    arguments: arguments,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) {
                    return
                }
                if let virtualInstruction = driver.callLowerer.tryEmitVirtualDispatch(
                    chosenCallee: callBinding.chosenCallee,
                    calleeName: calleeName,
                    receiverExpr: nil,
                    loweredReceiverID: lhs,
                    isSuperCall: false,
                    finalArguments: arguments,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner
                ) {
                    instructions.append(virtualInstruction)
                } else {
                    instructions.append(.call(
                        symbol: callBinding.chosenCallee,
                        callee: calleeName,
                        arguments: arguments,
                        result: result,
                        canThrow: false
                    ))
                }
            }

            if ast.arena.isIncrementDecrement(exprID) {
                let callResult = arena.appendTemporary(type: resultType)
                let operatorName = op == .plusAssign ? "inc" : "dec"
                let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                           !externalLinkName.isEmpty {
                    interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    symbol.name
                } else {
                    interner.intern(operatorName)
                }
                appendOperatorCall(
                    calleeName: loweredCalleeName,
                    arguments: [lhs],
                    result: callResult
                )
                return callResult
            }

            // `String?.plus(Any?)` is a bundled source wrapper around a
            // runtime bridge. Compound assignment must use the builtin
            // string conversion path so statically-known class/value-class
            // receivers retain their own `toString()` implementation.
            if driver.callLowerer.isBundledStringPlusCall(
                callBinding,
                op: op,
                sema: sema,
                interner: interner
            ) {
                return appendBuiltinCompoundResult(
                    lhs: lhs,
                    lhsType: arena.exprType(lhs) ?? sema.types.anyType,
                    rhs: rhs,
                    rhsType: arena.exprType(rhs)
                )
            }

            let normalizedResult = driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: [rhs],
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
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(lhs, at: 0)
            let callResult = arena.appendTemporary(type: resultType)
            let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                       !externalLinkName.isEmpty {
                interner.intern(externalLinkName)
            } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                symbol.name
            } else {
                interner.intern(op.kotlinFunctionName)
            }
            appendOperatorCall(
                calleeName: loweredCalleeName,
                arguments: finalArguments,
                result: callResult
            )
            return callResult
        }
        if let symbol = sema.bindings.identifierSymbols[exprID] {
            // Top-level or object-member property compound assignment
            // needs a copy to global storage.
            // `field` inside a custom getter/setter resolves to a
            // `.backingField`-kind symbol (see typeCheckGetter/typeCheckSetter
            // in DeclTypeChecker+PropertyHelpers.swift), so it must be
            // accepted here too — otherwise `field += x` on a top-level or
            // object property silently falls through to the generic local-
            // variable branch below, which only updates the compiler's
            // lowering-time local-value cache and never emits any
            // instruction that writes the backing field's global storage.
            if let delegateStorageID = driver.ctx.localDelegateStorage(for: symbol),
               let getValueSymbol = sema.symbols.delegateGetValueSymbol(for: symbol),
               let setValueSymbol = sema.symbols.delegateSetValueSymbol(for: symbol)
            {
                // Local delegated `var` compound assignment (BUG-147):
                // read-modify-write through the delegate's getValue/setValue.
                // Without this the generic local branch below would overwrite
                // the register that holds the delegate handle itself with the
                // arithmetic result.
                let propertyType = driver.ctx.localDeclaredType(for: symbol) ?? sema.types.anyType
                let getterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
                    localSymbol: symbol, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                )
                let loadedValue = arena.appendTemporary(type: propertyType)
                instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
                    symbol: getValueSymbol,
                    callee: interner.intern("getValue"),
                    receiver: delegateStorageID,
                    extraArguments: getterArgs,
                    result: loadedValue,
                    sema: sema,
                    interner: interner
                ))
                let rhsID = lowerRHS()
                let computedValue = appendBuiltinCompoundResult(
                    lhs: loadedValue,
                    lhsType: propertyType,
                    rhs: rhsID,
                    rhsType: arena.exprType(rhsID)
                )
                rememberIncrementDecrementResult(computedValue)
                let setterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
                    localSymbol: symbol, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                )
                let setResultExprID = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
                    symbol: setValueSymbol,
                    callee: interner.intern("setValue"),
                    receiver: delegateStorageID,
                    extraArguments: setterArgs + [computedValue],
                    result: setResultExprID,
                    sema: sema,
                    interner: interner
                ))
                // Reads always dispatch a fresh getValue (see
                // readLocalDelegateValue) rather than caching, so a
                // vetoable-style delegate rejecting this write is
                // observed correctly with no extra bookkeeping here.
            } else if !driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema),
                      !driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema),
                      let getterCallee = driver.callLowerer.enumPropertyGetterPlaceholder(
                          for: symbol, sema: sema, interner: interner
                      ),
                      let setterCallee = driver.callLowerer.enumPropertySetterPlaceholder(
                          for: symbol, sema: sema, interner: interner
                      ),
                      let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let loadedValue = arena.appendTemporary(type: propType)
                emitNonThrowingCall(callee: getterCallee, arg: receiverExprID, result: loadedValue, into: &instructions)
                func storeViaSetter(_ value: KIRExprID) {
                    instructions.append(.call(
                        callee: setterCallee,
                        arguments: [receiverExprID, value],
                        result: arena.appendTemporary(type: sema.types.unitType),
                        canThrow: false
                    ))
                }
                let rhsID = lowerRHS()
                if let callBinding = sema.bindings.callBindings[exprID],
                   let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                    if signature.returnType == sema.types.unitType {
                        _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                    } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                        storeViaSetter(resultID)
                        rememberIncrementDecrementResult(resultID)
                    }
                } else {
                    let resultID = appendBuiltinCompoundResult(
                        lhs: loadedValue,
                        lhsType: propType,
                        rhs: rhsID,
                        rhsType: arena.exprType(rhsID)
                    )
                    storeViaSetter(resultID)
                    rememberIncrementDecrementResult(resultID)
                }
            } else if let symInfo = sema.symbols.symbol(symbol),
                      symInfo.kind == .property,
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      let ownerInfo = sema.symbols.symbol(ownerSymbol),
                      ownerInfo.kind == .class || ownerInfo.kind == .interface,
                      let receiverExprID = driver.objectLiteralLowerer.implicitReceiverExprID(
                          forProperty: symbol,
                          sema: sema,
                          arena: arena
                      ),
                      driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema),
                      let read = lowerImplicitPropertyCompoundRead(
                          propertySymbol: symbol, receiver: receiverExprID, callExprID: exprID,
                          ast: ast, sema: sema, arena: arena, interner: interner,
                          instructions: &instructions
                      )
            {
                // Run a custom/delegated setter even when the getter uses
                // ordinary field storage. Keep the read and write halves
                // independent, as for explicit-receiver compound writes.
                let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let receiverExprID = read.receiver
                let loadedValue = read.value
                func storeViaSetter(_ value: KIRExprID) {
                    let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol)
                    let setResultExprID = arena.appendTemporary(type: sema.types.unitType)
                    let setterArguments = driver.callLowerer.propertyAccessorArguments(
                        for: setterSymbol, arguments: [receiverExprID, value], callExprID: exprID,
                        sema: sema, arena: arena, interner: interner, instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: setterSymbol,
                        callee: interner.intern("set"),
                        arguments: setterArguments,
                        result: setResultExprID,
                        canThrow: false
                    ))
                }
                let rhsID = lowerRHS()
                if let callBinding = sema.bindings.callBindings[exprID],
                   let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                    if signature.returnType == sema.types.unitType {
                        _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                    } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                        storeViaSetter(resultID)
                        rememberIncrementDecrementResult(resultID)
                    }
                } else {
                    let resultID = appendBuiltinCompoundResult(
                        lhs: loadedValue,
                        lhsType: propType,
                        rhs: rhsID,
                        rhsType: arena.exprType(rhsID)
                    )
                    storeViaSetter(resultID)
                    rememberIncrementDecrementResult(resultID)
                }
            } else if let symInfo = sema.symbols.symbol(symbol),
                      symInfo.kind == .property || symInfo.kind == .field || symInfo.kind == .backingField, {
                          let p = sema.symbols.parentSymbol(for: symbol)
                          let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                          return pk == nil || pk == .package || pk == .object
                      }() {
                let ownerSymbol = sema.symbols.parentSymbol(for: symbol)
                let parentKind = ownerSymbol.flatMap { sema.symbols.symbol($0)?.kind }
                let isObjectOwnedProperty = symInfo.kind == .property
                    && parentKind == .object
                    && !sema.bindings.isObjectLiteralPropertySymbol(symbol)
                if isObjectOwnedProperty, let ownerSymbol {
                    driver.emitObjectLazyInitGuardIfNeeded(
                        objectSymbol: ownerSymbol, arena: arena, sema: sema,
                        interner: interner,
                        instructions: &instructions
                    )
                }
                let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let backingFieldSymbol = isObjectOwnedProperty
                    ? sema.symbols.backingFieldSymbol(for: symbol)
                    : nil
                let objectReceiver: KIRExprID? = {
                    guard isObjectOwnedProperty, let ownerSymbol else { return nil }
                    let ownerType = sema.types.make(.classType(ClassType(
                        classSymbol: ownerSymbol, args: [], nullability: .nonNull
                    )))
                    let receiver = arena.appendExpr(.symbolRef(ownerSymbol), type: ownerType)
                    instructions.append(.constValue(result: receiver, value: .symbolRef(ownerSymbol)))
                    return receiver
                }()
                let usesGetterAccessor = isObjectOwnedProperty
                    && driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
                let setterSymbol: SymbolID? = if sema.symbols.symbol(symbol)?.kind == .property,
                                                 (parentKind == nil || parentKind == .package || isObjectOwnedProperty),
                                                 driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema)
                {
                    sema.symbols.extensionPropertySetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol)
                } else {
                    nil
                }
                let globalRef: KIRExprID?
                if setterSymbol == nil && backingFieldSymbol == nil {
                    let ref = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: ref, value: .symbolRef(symbol)))
                    globalRef = ref
                } else {
                    globalRef = nil
                }
                let loadedValue: KIRExprID
                if ast.arena.isIncrementDecrement(exprID),
                   let cachedValue = ast.arena.incrementDecrementCachedValue(for: exprID)
                {
                    loadedValue = lowerExpr(
                        cachedValue,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                } else if usesGetterAccessor, let ownerReceiver = objectReceiver {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    let result = arena.appendTemporary(type: propType)
                    driver.callLowerer.appendPropertyGetterCall(
                        getterSymbol: getterSymbol,
                        receiver: ownerReceiver,
                        callExprID: exprID,
                        result: result,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    loadedValue = result
                } else {
                    let storageSymbol = backingFieldSymbol ?? symbol
                    loadedValue = arena.appendExpr(.symbolRef(storageSymbol), type: propType)
                    instructions.append(.loadGlobal(result: loadedValue, symbol: storageSymbol))
                }
                let rhsID = lowerRHS()
                func storeGlobalResult(_ value: KIRExprID) {
                    if let setterSymbol {
                        var setterInputs = [value]
                        if let objectReceiver {
                            setterInputs.insert(objectReceiver, at: 0)
                        }
                        let setterArguments = driver.callLowerer.propertyAccessorArguments(
                            for: setterSymbol,
                            arguments: setterInputs,
                            callExprID: exprID,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        instructions.append(.call(
                            symbol: setterSymbol,
                            callee: interner.intern("set"),
                            arguments: setterArguments,
                            result: arena.appendTemporary(type: sema.types.unitType),
                            canThrow: false
                        ))
                    } else if let backingFieldSymbol {
                        let storedValue = normalizedValueForNullablePrimitiveSlot(
                            value,
                            slotType: sema.symbols.propertyType(for: backingFieldSymbol) ?? propType,
                            types: sema.types,
                            arena: arena,
                            into: &instructions
                        )
                        instructions.append(.storeGlobal(value: storedValue, symbol: backingFieldSymbol))
                    } else if let globalRef {
                        instructions.append(.copy(from: value, to: globalRef))
                    }
                }
                if let callBinding = sema.bindings.callBindings[exprID],
                   let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                    if signature.returnType == sema.types.unitType {
                        _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                    } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                        storeGlobalResult(resultID)
                        rememberIncrementDecrementResult(resultID)
                    }
                } else {
                    let resultID = appendBuiltinCompoundResult(
                        lhs: loadedValue,
                        lhsType: propType,
                        rhs: rhsID,
                        rhsType: arena.exprType(rhsID)
                    )
                    storeGlobalResult(resultID)
                    rememberIncrementDecrementResult(resultID)
                }
            } else if let symInfo = sema.symbols.symbol(symbol),
                      symInfo.kind == .property || symInfo.kind == .field,
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      let ownerInfo = sema.symbols.symbol(ownerSymbol),
                      ownerInfo.kind == .class || ownerInfo.kind == .interface,
                      let receiverID = driver.objectLiteralLowerer.implicitReceiverExprID(
                          forProperty: symbol,
                          sema: sema,
                          arena: arena
                      ),
                      let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                          sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                      ]
            {
                // Class/interface instance property compound assignment: the
                // property lives inside the heap-allocated instance, not in a
                // module-global slot, so the read-modify-write must go through
                // kk_array_get_inbounds / kk_array_set at the computed field
                // offset — mirroring tryLowerStoredMemberPropertyRead (reads)
                // and lowerMemberAssignExpr (plain `=` writes). Falling through
                // to the local-variable branch below would silently discard the
                // computed result instead of storing it back into the instance.
                //
                // BUG-inner-outer: an inner class's implicit receiver is its
                // own instance, but `counter++`/`counter += v` referencing a
                // property declared on an *enclosing* class must read/write
                // through the `$outer` chain instead of applying
                // `ownerSymbol`'s field offset to the wrong object. A no-op
                // for every other case, where the receiver already is (or
                // subclasses) `ownerSymbol`.
                let fieldReceiverExprID = resolveOuterChainValue(
                    from: receiverID,
                    to: ownerSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) ?? receiverID
                let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                let loadedValue = arena.appendTemporary(type: propType)
                instructions.append(.call(
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [fieldReceiverExprID, offsetExpr],
                    result: loadedValue,
                    canThrow: false
                ))
                func storeFieldResult(_ value: KIRExprID) {
                    let storedValue = normalizedValueForNullablePrimitiveSlot(
                        value,
                        slotType: propType,
                        types: sema.types,
                        arena: arena,
                        into: &instructions
                    )
                    instructions.append(.call(
                        callee: interner.intern("kk_array_set"),
                        arguments: [fieldReceiverExprID, offsetExpr, storedValue],
                        result: nil,
                        canThrow: false
                    ))
                }
                let rhsID = lowerRHS()
                if let callBinding = sema.bindings.callBindings[exprID],
                   let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                    if signature.returnType == sema.types.unitType {
                        _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                    } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                        storeFieldResult(resultID)
                        rememberIncrementDecrementResult(resultID)
                    }
                } else {
                    let resultID = appendBuiltinCompoundResult(
                        lhs: loadedValue,
                        lhsType: propType,
                        rhs: rhsID,
                        rhsType: arena.exprType(rhsID)
                    )
                    storeFieldResult(resultID)
                    rememberIncrementDecrementResult(resultID)
                }
            } else if driver.ctx.isMutableCaptureBoxed(symbol),
                      let loadedValue = loadMutableCaptureCellValue(
                          symbol: symbol,
                          resultType: {
                              driver.ctx.localDeclaredType(for: symbol)
                                  ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                          }(),
                          sema: sema,
                          arena: arena,
                          interner: interner,
                          instructions: &instructions
                      )
            {
                let symbolType = driver.ctx.localDeclaredType(for: symbol)
                    ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                let rhsID = lowerRHS()
                if let callBinding = sema.bindings.callBindings[exprID],
                   let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                    if signature.returnType == sema.types.unitType {
                        _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                    } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                        _ = storeMutableCaptureCellValue(
                            resultID,
                            for: symbol,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        rememberIncrementDecrementResult(resultID)
                    }
                } else {
                    let resultID = appendBuiltinCompoundResult(
                        lhs: loadedValue,
                        lhsType: symbolType,
                        rhs: rhsID,
                        rhsType: arena.exprType(rhsID)
                    )
                    _ = storeMutableCaptureCellValue(
                        resultID,
                        for: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    rememberIncrementDecrementResult(resultID)
                }
            } else if let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                          sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                      ]
            {
                // Instance field accessed via implicit `this` receiver: must load/store
                // through the object's field storage, mirroring the `.localAssign` write
                // path and the `nameRef` read path. Falling through to the plain-local
                // branch below would only update the compiler's local-value cache
                // (used for real locals/params), never the field itself, so the write
                // was silently dropped.
                let fieldType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                let rawLoadedValue = arena.appendTemporary(type: fieldType)
                instructions.append(.call(
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [receiverExprID, offsetExpr],
                    result: rawLoadedValue,
                    canThrow: false
                ))
                let loadedValue = wrapLateinitReadIfNeeded(
                    rawLoadedValue,
                    symbol: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                func storeField(_ value: KIRExprID) {
                    let storedValue = normalizedValueForNullablePrimitiveSlot(
                        value,
                        slotType: fieldType,
                        types: sema.types,
                        arena: arena,
                        into: &instructions
                    )
                    instructions.append(.call(
                        callee: interner.intern("kk_array_set"),
                        arguments: [receiverExprID, offsetExpr, storedValue],
                        result: nil,
                        canThrow: false
                    ))
                }
                let rhsID = lowerRHS()
                if let callBinding = sema.bindings.callBindings[exprID],
                   let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                    if signature.returnType == sema.types.unitType {
                        _ = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType)
                    } else if let resultID = appendOperatorCompoundResult(lhs: loadedValue, rhs: rhsID, resultType: signature.returnType) {
                        storeField(resultID)
                        rememberIncrementDecrementResult(resultID)
                    }
                } else {
                    let resultID = appendBuiltinCompoundResult(
                        lhs: loadedValue,
                        lhsType: fieldType,
                        rhs: rhsID,
                        rhsType: arena.exprType(rhsID)
                    )
                    storeField(resultID)
                    rememberIncrementDecrementResult(resultID)
                }
            } else {
                if sema.symbols.symbol(symbol)?.kind == .object {
                    // A bare object receiver is lowered directly from its
                    // singleton symbol here, so preserve the lazy-init guard
                    // that ordinary name-reference lowering would emit.
                    driver.emitObjectLazyInitGuardIfNeeded(
                        objectSymbol: symbol,
                        arena: arena,
                        sema: sema,
                        interner: interner,
                        instructions: &instructions
                    )
                }
                if let storageID = driver.ctx.localValue(for: symbol) {
                    // Compute lhs op rhs and update storage in place so the value
                    // persists across loop iterations.
                    let symbolType = driver.ctx.localDeclaredType(for: symbol)
                        ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                    let cachedIncrementValue: KIRExprID? = if ast.arena.isIncrementDecrement(exprID),
                        let cachedValue = ast.arena.incrementDecrementCachedValue(for: exprID)
                    {
                        driver.lowerExpr(
                            cachedValue,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            instructions: &instructions
                        )
                    } else {
                        nil
                    }
                    let operationType = cachedIncrementValue.flatMap { arena.exprType($0) } ?? symbolType
                    // `storageID` is this local's persistent storage register,
                    // returned by identity (not a value snapshot). If the RHS
                    // mutates the same local in place (e.g. `y += y++ + ++y`),
                    // lowering it before reading the current value here would
                    // let this read observe the RHS's own mutation instead of
                    // the value Kotlin's left-to-right evaluation order
                    // requires. Freeze it into a fresh temporary first.
                    let checkedValue: KIRExprID
                    if let cachedIncrementValue {
                        checkedValue = cachedIncrementValue
                    } else {
                        checkedValue = wrapLateinitReadIfNeeded(
                            storageID, symbol: symbol, sema: sema, arena: arena,
                            interner: interner, instructions: &instructions
                        )
                    }
                    // Erased local storage retains its declared type (for
                    // example `Any`), while sema records the flow-refined LHS
                    // type for this assignment. Unbox smartcasted primitives
                    // before computing the result, then box on the copy back
                    // to the declared storage slot.
                    let operationValue = driver.callLowerer.materializeSmartcastedPrimitiveValue(
                        checkedValue,
                        boundType: sema.bindings.compoundAssignReceiverType(for: exprID),
                        sema: sema,
                        arena: arena,
                        instructions: &instructions
                    ) ?? checkedValue
                    let lhsType = arena.exprType(operationValue) ?? operationType
                    let frozenLHS = arena.appendTemporary(type: lhsType)
                    instructions.append(.copy(from: operationValue, to: frozenLHS))
                    let rhsID = lowerRHS()
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: frozenLHS, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: frozenLHS, rhs: rhsID, resultType: signature.returnType) {
                            let storedValue = ast.arena.isIncrementDecrement(exprID)
                                ? normalizedValueForNullablePrimitiveSlot(
                                    resultID,
                                    slotType: symbolType,
                                    types: sema.types,
                                    arena: arena,
                                    into: &instructions
                                )
                                : resultID
                            instructions.append(.copy(from: storedValue, to: storageID))
                            rememberIncrementDecrementResult(resultID)
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: frozenLHS,
                            lhsType: lhsType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        let storedValue = ast.arena.isIncrementDecrement(exprID)
                            ? normalizedValueForNullablePrimitiveSlot(
                                resultID,
                                slotType: symbolType,
                                types: sema.types,
                                arena: arena,
                                into: &instructions
                            )
                            : resultID
                        instructions.append(.copy(from: storedValue, to: storageID))
                        rememberIncrementDecrementResult(resultID)
                    }
                } else {
                    let symbolType = driver.ctx.localDeclaredType(for: symbol)
                        ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                    let lhsID = arena.appendExpr(.symbolRef(symbol), type: symbolType)
                    instructions.append(.constValue(result: lhsID, value: .symbolRef(symbol)))
                    let rhsID = lowerRHS()
                    if let callBinding = sema.bindings.callBindings[exprID],
                       let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee) {
                        if signature.returnType == sema.types.unitType {
                            _ = appendOperatorCompoundResult(lhs: lhsID, rhs: rhsID, resultType: signature.returnType)
                        } else if let resultID = appendOperatorCompoundResult(lhs: lhsID, rhs: rhsID, resultType: signature.returnType) {
                            driver.ctx.setLocalValue(resultID, for: symbol)
                            rememberIncrementDecrementResult(resultID)
                        }
                    } else {
                        let resultID = appendBuiltinCompoundResult(
                            lhs: lhsID,
                            lhsType: symbolType,
                            rhs: rhsID,
                            rhsType: arena.exprType(rhsID)
                        )
                        driver.ctx.setLocalValue(resultID, for: symbol)
                        rememberIncrementDecrementResult(resultID)
                    }
                }
            }
        }
        if let incrementDecrementResult {
            return incrementDecrementResult
        }
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
