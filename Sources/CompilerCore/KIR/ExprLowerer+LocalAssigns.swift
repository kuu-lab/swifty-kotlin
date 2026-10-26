extension ExprLowerer {
    func lowerLocalAssign(
        valueExpr: ExprID,
        exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let valueID = lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        if let symbol = sema.bindings.identifierSymbols[exprID] {
            // Check if this is a top-level or object-member property assignment.
            // These need a copy to global storage rather than just updating
            // localValuesBySymbol (which wouldn't persist across function calls).
            if let delegateStorageID = driver.ctx.localDelegateStorage(for: symbol),
               let setValueSymbol = sema.symbols.delegateSetValueSymbol(for: symbol)
            {
                // Local delegated `var` (BUG-014 / KSP-CAP-007 / BUG-052): `x = value`
                // calls `Prop().setValue(null, KProperty("x"), value)`, mirroring
                // the getValue call synthesized at the declaration in the
                // `.localDecl` case, instead of overwriting x's storage register.
                let setterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
                    localSymbol: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                let setResultExprID = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
                    symbol: setValueSymbol,
                    callee: interner.intern("setValue"),
                    receiver: delegateStorageID,
                    extraArguments: setterArgs + [valueID],
                    result: setResultExprID,
                    sema: sema,
                    interner: interner
                ))
                // Reads always dispatch a fresh getValue (see
                // readLocalDelegateValue) rather than caching, so a
                // vetoable-style delegate rejecting this write is
                // observed correctly with no extra bookkeeping here.
            } else if sema.symbols.classDelegationForwardingPropertyInfo(for: symbol) != nil,
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      sema.symbols.symbol(ownerSymbol)?.kind == .object
            {
                let ownerType = sema.types.make(.classType(ClassType(
                    classSymbol: ownerSymbol, args: [], nullability: .nonNull
                )))
                let receiver = arena.appendExpr(.symbolRef(ownerSymbol), type: ownerType)
                instructions.append(.constValue(result: receiver, value: .symbolRef(ownerSymbol)))
                instructions.append(.call(
                    symbol: SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol),
                    callee: interner.intern("set"),
                    arguments: [receiver, valueID],
                    result: nil,
                    canThrow: false
                ))
            } else if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .backingField, {
                let parent = sema.symbols.parentSymbol(for: symbol)
                let parentKind = parent.flatMap { sema.symbols.symbol($0)?.kind }
                return parentKind == nil || parentKind == .package || parentKind == .object
            }() {
                // Accessor `field` references bind directly to a backing-field
                // symbol. Store global-backed fields directly because copies
                // to backing-field symbols are rewritten as property setter calls.
                let storedValueID = normalizedValueForNullablePrimitiveSlot(
                    valueID,
                    slotType: sema.symbols.propertyType(for: symbol) ?? sema.types.anyType,
                    types: sema.types,
                    arena: arena,
                    into: &instructions
                )
                instructions.append(.storeGlobal(value: storedValueID, symbol: symbol))
            } else if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .property, {
                let parent = sema.symbols.parentSymbol(for: symbol)
                let parentKind = parent.flatMap { sema.symbols.symbol($0)?.kind }
                return parentKind == nil || parentKind == .package || parentKind == .object
            }(), driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema) {
                let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: symbol)
                    ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol)
                var setterInputs = [valueID]
                if let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   sema.symbols.symbol(ownerSymbol)?.kind == .object,
                   !sema.bindings.isObjectLiteralPropertySymbol(symbol)
                {
                    // Bare references to singleton properties omit the dispatch receiver.
                    driver.emitObjectLazyInitGuardIfNeeded(
                        objectSymbol: ownerSymbol,
                        arena: arena,
                        sema: sema,
                        interner: interner,
                        instructions: &instructions
                    )
                    let ownerType = sema.types.make(.classType(ClassType(
                        classSymbol: ownerSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    let receiver = arena.appendExpr(.symbolRef(ownerSymbol), type: ownerType)
                    instructions.append(.constValue(result: receiver, value: .symbolRef(ownerSymbol)))
                    setterInputs.insert(receiver, at: 0)
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
            } else if let symInfo = sema.symbols.symbol(symbol), symInfo.kind == .property || symInfo.kind == .field, {
                let p = sema.symbols.parentSymbol(for: symbol)
                let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                return pk == nil || pk == .package || pk == .object
            }() {
                if symInfo.kind == .property,
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   sema.symbols.symbol(ownerSymbol)?.kind == .object,
                   !sema.bindings.isObjectLiteralPropertySymbol(symbol)
                {
                    // A bare imported property still triggers object initialization,
                    // just like a qualified object-member write. Otherwise a later
                    // read can run the initializer and overwrite this assignment.
                    driver.emitObjectLazyInitGuardIfNeeded(
                        objectSymbol: ownerSymbol,
                        arena: arena,
                        sema: sema,
                        interner: interner,
                        instructions: &instructions
                    )
                }
                if sema.symbols.symbol(symbol)?.kind == .property,
                   let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol)
                {
                    // A custom getter with no custom setter still has the
                    // compiler-provided setter, which writes the backing field.
                    // Keep bare assignments on that same storage so later
                    // getter calls observe the new value.
                    let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol)
                        ?? sema.symbols.propertyType(for: symbol)
                        ?? sema.types.anyType
                    let storedValueID = normalizedValueForNullablePrimitiveSlot(
                        valueID,
                        slotType: backingFieldType,
                        types: sema.types,
                        arena: arena,
                        into: &instructions
                    )
                    instructions.append(.storeGlobal(value: storedValueID, symbol: backingFieldSymbol))
                } else {
                    let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                    let globalRef = arena.appendExpr(.symbolRef(symbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(symbol)))
                    instructions.append(.copy(from: valueID, to: globalRef))
                }
            } else if let slotSymbol = driver.ctx.enumEntryStorageSlots[symbol] {
                let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: propType)
                instructions.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
                instructions.append(.copy(from: valueID, to: slotRef))
            } else if sema.symbols.symbol(symbol)?.kind == .property,
                      !driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema),
                      let setterCallee = driver.callLowerer.enumPropertySetterPlaceholder(
                          for: symbol, sema: sema, interner: interner
                      ),
                      let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                instructions.append(.call(
                    callee: setterCallee,
                    arguments: [receiverExprID, valueID],
                    result: arena.appendTemporary(type: sema.types.unitType),
                    canThrow: false
                ))
            } else if storeMutableCaptureCellValue(
                valueID,
                for: symbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
            } else if let receiverExprID = driver.objectLiteralLowerer.implicitReceiverExprID(
                forProperty: symbol,
                sema: sema,
                arena: arena
            ),
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      sema.symbols.symbol(ownerSymbol)?.kind == .interface,
                      driver.callLowerer.tryLowerInterfaceItablePropertySetterWrite(
                          propertySymbol: symbol,
                          loweredReceiverID: receiverExprID,
                          loweredValueID: valueID,
                          sema: sema,
                          cache: driver.ctx.nominalDispatchCache,
                          arena: arena,
                          interner: interner,
                          instructions: &instructions
                      ) != nil
            {
                // Bare interface-property writes in nested receiver lambdas
                // must dispatch through the captured implementing instance.
            } else if let receiverExprID = driver.objectLiteralLowerer.implicitReceiverExprID(
                forProperty: symbol,
                sema: sema,
                arena: arena
            ),
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      let ownerInfo = sema.symbols.symbol(ownerSymbol),
                      ownerInfo.kind == .class || ownerInfo.kind == .interface,
                      !(
                          sema.symbols.symbol(symbol)?.kind == .property
                              && driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema)
                      ),
                      let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                          sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                      ]
            {
                // BUG-inner-outer: see the read-side fix above -- a
                // bare `counter = value` referencing a property
                // declared on an *enclosing* class must write through
                // the `$outer` chain instead of applying
                // `ownerSymbol`'s field offset to the wrong object.
                let fieldReceiverExprID = resolveOuterChainValue(
                    from: receiverExprID,
                    to: ownerSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) ?? receiverExprID
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                let storedValueID = normalizedValueForNullablePrimitiveSlot(
                    valueID,
                    slotType: sema.symbols.propertyType(for: symbol) ?? sema.types.anyType,
                    types: sema.types,
                    arena: arena,
                    into: &instructions
                )
                instructions.append(.call(
                    callee: interner.intern("kk_array_set"),
                    arguments: [fieldReceiverExprID, offsetExpr, storedValueID],
                    result: nil,
                    canThrow: false
                ))
            } else if let receiverExprID = driver.objectLiteralLowerer.implicitReceiverExprID(
                forProperty: symbol,
                sema: sema,
                arena: arena
            ),
                      let symInfo = sema.symbols.symbol(symbol),
                      symInfo.kind == .property,
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      let ownerInfo = sema.symbols.symbol(ownerSymbol),
                      ownerInfo.kind == .class || ownerInfo.kind == .interface
            {
                // A missing field offset can mean an accessor-backed class
                // property or an interface property, which has no per-instance
                // layout. Resolve interface writes through its itable setter;
                // class properties use their setter body or backing field.
                // (`.object` is deliberately excluded: the branch above
                // already routes every object-member property through
                // global-copy storage before reaching here.)
                if ownerInfo.kind == .interface,
                   driver.callLowerer.tryLowerInterfaceItablePropertySetterWrite(
                       propertySymbol: symbol,
                       loweredReceiverID: receiverExprID,
                       loweredValueID: valueID,
                       sema: sema,
                       cache: driver.ctx.nominalDispatchCache,
                       arena: arena,
                       interner: interner,
                       instructions: &instructions
                   ) != nil
                {
                    // An interface has no instance field layout of its own.
                    // A bare property name in a nested lambda still refers to
                    // the captured dispatch receiver, so write through its
                    // runtime itable setter just like an explicit receiver.
                } else if driver.callLowerer.memberPropertyUsesSetterAccessor(symbol, ast: ast, sema: sema) {
                    let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol)
                    let setterArguments = driver.callLowerer.propertyAccessorArguments(
                        for: setterSymbol, arguments: [receiverExprID, valueID], callExprID: exprID,
                        sema: sema, arena: arena, interner: interner, instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: setterSymbol,
                        callee: interner.intern("set"),
                        arguments: setterArguments,
                        result: nil,
                        canThrow: false
                    ))
                } else if let backingFieldSym = sema.symbols.backingFieldSymbol(for: symbol) {
                    // Deliberately `.storeGlobal`, not `.copy(to: .symbolRef(...))`:
                    // PropertyLoweringPass rewrites any `.copy` targeting a
                    // `.backingField`-kind symbolRef into a setter-accessor
                    // call, which would misfire here since no setter
                    // accessor function was emitted for this property. The
                    // value still goes through a property-typed `.copy`
                    // temporary first so a `P?` backing field keeps its
                    // box-or-sentinel invariant (KUU-854).
                    let storedValueID = normalizedValueForNullablePrimitiveSlot(
                        valueID,
                        slotType: sema.symbols.propertyType(for: symbol) ?? sema.types.anyType,
                        types: sema.types,
                        arena: arena,
                        into: &instructions
                    )
                    instructions.append(.storeGlobal(value: storedValueID, symbol: backingFieldSym))
                } else if let storageID = driver.ctx.localValue(for: symbol) {
                    // Neither a real setter nor a backing field exists (e.g. an
                    // abstract property with no accessor of its own): fall back
                    // to the same treatment as the outer `else` below rather than
                    // silently dropping the write, since this `else if` already
                    // claimed the assignment and nothing after it will run.
                    instructions.append(.copy(from: valueID, to: storageID))
                } else {
                    driver.ctx.setLocalValue(valueID, for: symbol)
                }
            } else {
                if let storageID = driver.ctx.localValue(for: symbol) {
                    // Mutable local already has storage: emit a copy so the C variable
                    // is updated in place, preserving the value across loop iterations.
                    instructions.append(.copy(from: valueID, to: storageID))
                    // Reassigning a callable-typed local to a different lambda/function
                    // reference must overwrite storageID's callableValueInfo too, or a
                    // later call through this local would still invoke the previous value.
                    if let callableInfo = driver.ctx.callableValueInfo(for: valueID) {
                        driver.ctx.callableValueInfoByExprID[storageID] = callableInfo
                    } else {
                        driver.ctx.callableValueInfoByExprID.removeValue(forKey: storageID)
                    }
                } else {
                    // An initializer-less local has no storage until this
                    // assignment. Bind it to a slot of its declared type
                    // instead of aliasing the RHS register: later writes to
                    // either variable update that register in place.
                    let localSlot = arena.appendTemporary(
                        type: driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                    )
                    instructions.append(.copy(from: valueID, to: localSlot))
                    driver.ctx.setLocalValue(localSlot, for: symbol)
                    if let callableInfo = driver.ctx.callableValueInfo(for: valueID) {
                        driver.ctx.callableValueInfoByExprID[localSlot] = callableInfo
                    }
                }
            }
        }
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
