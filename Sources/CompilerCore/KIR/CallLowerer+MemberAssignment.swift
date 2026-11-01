
extension CallLowerer {
    /// The bundled `kotlin.text.String?.plus(Any?)` declaration is a source
    /// wrapper around a runtime bridge, but compound assignment must still use
    /// the compiler's string-concatenation conversion funnel. That funnel
    /// preserves statically-known class/value-class `toString()` dispatch;
    /// passing the raw value to `__kk_string_plus` loses that type information.
    func isBundledStringPlusCall(
        _ callBinding: CallBinding?,
        op: CompoundAssignOp,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard op == .plusAssign,
              let chosenCallee = callBinding?.chosenCallee,
              let symbol = sema.symbols.symbol(chosenCallee),
              symbol.kind == .function,
              sema.symbols.isSourceBackedSymbol(chosenCallee)
        else {
            return false
        }
        let expectedFQName = [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("plus"),
        ]
        return symbol.fqName == expectedFQName
    }


    /// A setter declared with an erased type parameter (`Base<T>.x: T`) takes
    /// its value boxed, like a generic method argument: an override's vtable
    /// bridge checkcasts and unboxes it, and a raw `-0.0` or `Long.MIN_VALUE`
    /// would read as the null sentinel there.
    private func erasedVirtualSetterValue(
        _ value: KIRExprID,
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let declaredType = sema.symbols.propertyType(for: propertySymbol),
              kirIsNonReifiedErasedABIType(declaredType, sema: sema),
              let valueType = arena.exprType(value)
        else {
            return value
        }
        return boxValueForAnySlot(
            value, sourceType: valueType, types: sema.types, symbols: sema.symbols,
            interner: interner, arena: arena, sema: sema, into: &instructions
        )
    }

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
        instructions: inout [KIRInstruction],
        precomputedReceiverID: KIRExprID? = nil
    ) -> KIRExprID {
        let receiverID = precomputedReceiverID ?? driver.lowerExpr(
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
        // (e.g. AtomicBoolean.value → __kk_atomic_bool_load) must route their
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
            instructions.append(.call(callee: interner.intern(storeLinkName), arguments: [receiverID, valueID], result: nil, canThrow: false))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID)
                ?? sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true,
           let receiverType = sema.bindings.exprTypes[receiverExpr],
           let (_, receiverClassSymbol) = resolveClassTypeSymbol(
               sema.types.makeNonNullable(receiverType), sema: sema
           ),
           receiverClassSymbol.kind == .enumClass
        {
            let setter = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
            if let dispatch = kirEnumEntryDispatchHelper(
                for: setter,
                in: receiverClassSymbol.id,
                sema: sema,
                interner: interner
            ), let dispatchInfo = sema.symbols.symbol(dispatch) {
                let result = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.call(
                    symbol: dispatch,
                    callee: dispatchInfo.name,
                    arguments: [receiverID, valueID],
                    result: result,
                    canThrow: true
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
        }
        // Custom setters and delegated properties must run before direct
        // storage paths so their bodies (or the delegate's `setValue`) observe
        // explicit-receiver assignments as Kotlin does.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           // Interface-owned accessors must fall through to the itable path
           // below; imported metadata can mark abstract setters as accessor-backed.
           ownerInfo.kind == .class || ownerInfo.kind == .object,
           memberPropertyUsesSetterAccessor(propertySymbol, ast: ast, sema: sema)
        {
            // BUG-227: an open/abstract/override property with a custom
            // setter whose owner has known subtypes must dispatch through the
            // setter's vtable slot, exactly like the getter side — a direct
            // call always runs *this* declaration's own setter body,
            // regardless of the receiver's actual runtime type.
            if let (accessorSymbol, dispatch) = tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .setter,
                ast: ast,
                sema: sema,
                interner: interner
            ) {
                let result = arena.appendTemporary(type: sema.types.unitType)
                let setterValueID = erasedVirtualSetterValue(
                    valueID, propertySymbol: propertySymbol,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                let virtualAccessorArguments = propertyAccessorArguments(
                    for: accessorSymbol, arguments: [receiverID, setterValueID], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.virtualCall(
                    symbol: accessorSymbol,
                    callee: interner.intern("set"),
                    receiver: virtualAccessorArguments[0],
                    arguments: Array(virtualAccessorArguments.dropFirst()),
                    result: result,
                    canThrow: false,
                    dispatch: dispatch
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
            let result = arena.appendTemporary(type: sema.types.unitType)
            let setterArguments = propertyAccessorArguments(
                for: setterSymbol, arguments: [receiverID, valueID], callExprID: exprID,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            instructions.append(.call(
                symbol: setterSymbol,
                callee: interner.intern("set"),
                arguments: setterArguments,
                result: result,
                canThrow: false
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Extension `var` properties have no backing storage; assignment
        // routes to the registered setter accessor with the receiver as its
        // first argument. Prefer the identifier binding, with the selected
        // callee as a fallback for call-bound property l-values. Library
        // imports also register member-property accessors in this table, so
        // interface properties must continue to the itable dispatch path
        // below instead of calling the interface setter directly.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID)
            ?? sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.parentSymbol(for: propertySymbol).flatMap({ sema.symbols.symbol($0) })?.kind != .interface,
           let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
        {
            let result = arena.appendTemporary(type: sema.types.unitType)
            let setterArguments = propertyAccessorArguments(
                for: setterSymbol, arguments: [receiverID, valueID], callExprID: exprID,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            instructions.append(.call(
                symbol: setterSymbol,
                callee: interner.intern("set"),
                arguments: setterArguments,
                result: result,
                canThrow: false
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // `object` member properties are stored as flat global slots. An
        // accessor-backed property uses its separate backing-field symbol,
        // matching object reads and bare-name assignments. The heap object
        // some objects allocate via `kk_object_new` (for interface/vtable
        // dispatch) never holds the object's own stored properties, so it must
        // not be treated as field-offset storage here. A local `object`
        // (KUU-555) is the exception: its members are object-literal instance
        // fields, so the `.object` owner check must skip them and let the
        // field-offset storage path below handle the write.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           !sema.bindings.isObjectLiteralPropertySymbol(propertySymbol),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .object
        {
            let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            if let backingField = sema.symbols.backingFieldSymbol(for: propertySymbol) {
                let storedValue = normalizedValueForNullablePrimitiveSlot(
                    valueID,
                    slotType: sema.symbols.propertyType(for: backingField) ?? propType,
                    types: sema.types,
                    arena: arena,
                    into: &instructions
                )
                instructions.append(.storeGlobal(value: storedValue, symbol: backingField))
            } else {
                let globalRef = arena.appendExpr(.symbolRef(propertySymbol), type: propType)
                instructions.append(.constValue(result: globalRef, value: .symbolRef(propertySymbol)))
                instructions.append(.copy(from: valueID, to: globalRef))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface
               || (ownerInfo.kind == .object && sema.bindings.isObjectLiteralPropertySymbol(propertySymbol))
        {
            // KUU-3522: `super.foo = value` on an interface property must
            // invoke the syntactically selected supertype's default setter
            // directly. Itable dispatch targets the receiver's runtime
            // override — inside an overriding accessor that is this very
            // setter, so the call recurses until the process traps. This
            // mirrors the read side, where `isSuperQualifiedReceiver`
            // bypasses `tryLowerInterfaceItablePropertyGetterRead` for a
            // direct accessor call.
            if case .superRef = ast.arena.expr(receiverExpr),
               ownerInfo.kind == .interface,
               memberPropertyUsesSetterAccessor(propertySymbol, ast: ast, sema: sema)
            {
                let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                    ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
                let result = arena.appendTemporary(type: sema.types.unitType)
                let setterArguments = propertyAccessorArguments(
                    for: setterSymbol, arguments: [receiverID, valueID], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.call(
                    symbol: setterSymbol,
                    callee: interner.intern("set"),
                    arguments: setterArguments,
                    result: result,
                    canThrow: false
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            // An interface has no per-instance storage of its own, so a
            // stored/abstract `var` written through an interface-typed
            // receiver cannot use a concrete field offset (the same reason
            // `tryLowerInterfaceItablePropertyGetterRead` exists for reads).
            // Dispatch through the interface's itable to the implementing
            // type's setter instead of falling through to the field-offset
            // lookup below (which finds nothing on an interface) and then
            // the generic call-binding fallback at the bottom of this
            // function (which linked against an undefined name).
            if let result = tryLowerInterfaceItablePropertySetterWrite(
                propertySymbol: propertySymbol,
                loweredReceiverID: receiverID,
                loweredValueID: valueID,
                sema: sema,
                cache: driver.ctx.nominalDispatchCache,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
                return result
            }
            // BUG-227: a stored open/abstract/override property whose owner
            // has known subtypes must dispatch through its setter's vtable
            // slot — the field offset below is only this declaration's own
            // storage, which is correct only when no runtime-type override
            // can be in play.
            if let (accessorSymbol, dispatch) = tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .setter,
                ast: ast,
                sema: sema,
                interner: interner
            ) {
                let result = arena.appendTemporary(type: sema.types.unitType)
                let setterValueID = erasedVirtualSetterValue(
                    valueID, propertySymbol: propertySymbol,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                let virtualAccessorArguments = propertyAccessorArguments(
                    for: accessorSymbol, arguments: [receiverID, setterValueID], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.virtualCall(
                    symbol: accessorSymbol,
                    callee: interner.intern("set"),
                    receiver: virtualAccessorArguments[0],
                    arguments: Array(virtualAccessorArguments.dropFirst()),
                    result: result,
                    canThrow: false,
                    dispatch: dispatch
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            if let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            ] {
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                let storedValueID = normalizedValueForNullablePrimitiveSlot(
                    valueID,
                    slotType: sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType,
                    types: sema.types,
                    arena: arena,
                    into: &instructions
                )
                instructions.append(.call(
                    callee: interner.intern("kk_array_set"),
                    arguments: [receiverID, offsetExpr, storedValueID],
                    result: nil,
                    canThrow: false
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
        }
        let enumConstructorOwner = driver.ctx.currentFunctionSymbol.flatMap { functionSymbol -> SymbolID? in
            guard sema.symbols.symbol(functionSymbol)?.kind == .constructor,
                  let ownerSymbol = sema.symbols.parentSymbol(for: functionSymbol),
                  sema.symbols.symbol(ownerSymbol)?.kind == .enumClass
            else {
                return nil
            }
            return ownerSymbol
        }
        let boundPropertySymbol = sema.bindings.identifierSymbol(for: exprID)
            .flatMap { symbol -> SymbolID? in
                sema.symbols.symbol(symbol)?.kind == .property ? symbol : nil
            }
        let enumPropertySymbol = boundPropertySymbol ?? enumConstructorOwner.flatMap { ownerSymbol in
            guard let ownerInfo = sema.symbols.symbol(ownerSymbol) else { return nil }
            return sema.symbols.lookupAll(fqName: ownerInfo.fqName + [calleeName])
                .first(where: { sema.symbols.symbol($0)?.kind == .property })
        }
        // Sema cannot bind constructor-time writes to an immutable member to
        // a setter. During `$enumEnsureInit$`, use the active entry's slot;
        // elsewhere in an enum constructor, route through the synthetic setter
        // emitted for its body property.
        let enumStorageTarget: (property: SymbolID, slot: SymbolID)? = {
            if let propertySymbol = enumPropertySymbol,
               let slotSymbol = driver.ctx.enumEntryStorageSlots[propertySymbol]
            {
                return (propertySymbol, slotSymbol)
            }
            return driver.ctx.enumEntryStorageSlots.first { propertySymbol, _ in
                guard let info = sema.symbols.symbol(propertySymbol) else { return false }
                return info.kind == .property && info.name == calleeName
            }.map { ($0.key, $0.value) }
        }()
        if let enumStorageTarget {
            let propertyType = sema.symbols.propertyType(for: enumStorageTarget.property) ?? sema.types.anyType
            let slot = arena.appendExpr(.symbolRef(enumStorageTarget.slot), type: propertyType)
            instructions.append(.constValue(result: slot, value: .symbolRef(enumStorageTarget.slot)))
            instructions.append(.copy(from: valueID, to: slot))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Enum `var` properties, and body `val` assignments in secondary
        // constructors, use ordinal-backed setter helpers when no entry slot
        // is active in the current lowering scope.
        if let propertySymbol = enumPropertySymbol,
           let setterCallee = enumPropertySetterPlaceholder(
               for: propertySymbol,
               allowValInitialization: enumConstructorOwner != nil,
               sema: sema,
               interner: interner
           )
        {
            instructions.append(.call(
                callee: setterCallee,
                arguments: [receiverID, valueID],
                result: arena.appendTemporary(type: sema.types.unitType),
                canThrow: false
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
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
        instructions.append(.call(symbol: chosenCallee, callee: setterName, arguments: [receiverID, valueID], result: result, canThrow: false))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerSafeMemberAssignExpr(
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
        instructions.append(.jump(endLabel))
        instructions.append(.label(nonNullLabel))
        _ = lowerMemberAssignExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            valueExpr: valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions,
            precomputedReceiverID: receiverID
        )
        instructions.append(.label(endLabel))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }


    /// Lowers `receiver.field op= value` (and the desugared form of
    /// `receiver.field++` / `receiver.field--`) as load -> compute -> store,
    /// evaluating `receiver` exactly once. The load and store sides mirror
    /// `lowerMemberAssignExpr`'s safe, well-defined storage strategies,
    /// falling back to a best-effort setter/getter name for anything else, the
    /// same fallback (and the same pre-existing limitations for custom
    /// accessors reached through an explicit receiver) that plain member
    /// assignment already relies on.
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

        let propertySymbol = sema.bindings.identifierSymbol(for: exprID)
        let declaredPropType = propertySymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.bindings.exprTypes[exprID]
            ?? sema.types.anyType
        // A generic owner's property (`Holder<Int>.value: T`) is declared with
        // the erased type parameter; reads/writes must be typed with the
        // receiver-specialized type (`Int`) so the ABI passes box/unbox the
        // itable/vtable accessor boundary the same way a plain read does.
        let propType: TypeID = {
            guard let propertySymbol,
                  let receiverType = sema.bindings.exprTypes[receiverExpr],
                  let specialized = TypeCheckHelpers().lookupMemberPropertyForWrite(
                      named: calleeName,
                      receiverType: sema.types.makeNonNullable(receiverType),
                      sema: sema
                  ),
                  (specialized.writeSymbol ?? specialized.symbol) == propertySymbol
            else {
                return declaredPropType
            }
            return specialized.type
        }()
        let stringType = sema.types.stringType
        let nullableStringType = sema.types.makeNullable(stringType)
        // `String += Any?` is the language-level concatenation operation, not
        // an ordinary receiver call. Sema may bind the desugared expression to
        // the bundled `String?.plus` extension, but passing the loaded field as
        // that receiver bypasses the Any-to-String conversion funnel below.
        // Keep the builtin path for String fields so class/value/primitive RHS
        // values are rendered with their Kotlin `toString()` semantics.
        let usesBuiltinStringCompound = op == .plusAssign
            && (propType == stringType || propType == nullableStringType)

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

        // `object` member properties use flat global slots rather than
        // per-instance field-offset storage (see `lowerMemberAssignExpr`).
        let isObjectOwned: Bool = {
            guard syntheticLinks == nil,
                  let propertySymbol,
                  !sema.bindings.isObjectLiteralPropertySymbol(propertySymbol),
                  let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
                  let ownerInfo = sema.symbols.symbol(ownerSymbol)
            else {
                return false
            }
            return ownerInfo.kind == .object
        }()

        // Properties whose reads and writes go through accessors (custom
        // get/set bodies, delegated properties) have no usable backing storage
        // for a load/compute/store round trip.
        // The two halves are independent: a custom setter with a default
        // getter (or vice versa) has no accessor symbol for the default half,
        // so that half must keep using the backing field directly.
        let usesGetterAccessor: Bool = {
            guard let propertySymbol else { return false }
            return memberPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema)
        }()
        let usesSetterAccessor: Bool = {
            guard let propertySymbol else { return false }
            return sema.symbols.extensionPropertySetterAccessor(for: propertySymbol) != nil
                || memberPropertyUsesSetterAccessor(propertySymbol, ast: ast, sema: sema)
                || sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol) != nil
                || sema.symbols.extensionPropertySetterAccessor(for: propertySymbol) != nil
        }()
        // A custom getter or default setter still uses the property's backing
        // storage for the store half; only a declared/imported setter body
        // may replace the object's flat-global write. `usesSetterAccessor`
        // above intentionally over-approximates (a getter accessor counts)
        // for the enum-helper gate, so this narrower predicate decides
        // whether `call set` has a real accessor function to reach.
        let storeUsesSetterAccessor: Bool = {
            guard let propertySymbol else { return false }
            return sema.symbols.extensionPropertySetterAccessor(for: propertySymbol) != nil
                || memberPropertyUsesSetterAccessor(propertySymbol, ast: ast, sema: sema)
        }()

        // Enum stored properties: load/store through the enum property
        // helpers (per-entry storage), never through field offsets.
        let enumHelperCallees: (getter: InternedString, setter: InternedString)? = {
            guard syntheticLinks == nil,
                  !usesGetterAccessor,
                  !usesSetterAccessor,
                  let propertySymbol,
                  let getter = enumPropertyGetterPlaceholder(for: propertySymbol, sema: sema, interner: interner),
                  let setter = enumPropertySetterPlaceholder(for: propertySymbol, sema: sema, interner: interner)
            else {
                return nil
            }
            return (getter, setter)
        }()

        let fieldOffset: Int? = {
            guard syntheticLinks == nil,
                  !isObjectOwned,
                  let propertySymbol,
                  let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
                  let ownerInfo = sema.symbols.symbol(ownerSymbol),
                  ownerInfo.kind == .class || ownerInfo.kind == .interface
                      || (ownerInfo.kind == .object && sema.bindings.isObjectLiteralPropertySymbol(propertySymbol))
            else {
                return nil
            }
            return sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            ]
        }()

        // BUG-227: an open/abstract/override property whose owner has known
        // subtypes must dispatch both the read and the write half of this
        // compound assignment through the getter/setter's vtable slot —
        // mirroring `lowerMemberAssignExpr`'s identical treatment of a plain
        // (`=`) assignment. Resolved once up front since both the load and
        // store sections below need it.
        let virtualGetterDispatch = propertySymbol.flatMap { propertySymbol in
            tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .getter,
                ast: ast,
                sema: sema,
                interner: interner
            )
        }
        let virtualSetterDispatch = propertySymbol.flatMap { propertySymbol in
            tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .setter,
                ast: ast,
                sema: sema,
                interner: interner
            )
        }

        let currentValue: KIRExprID
        if let cachedValue = ast.arena.incrementDecrementCachedValue(for: exprID) {
            currentValue = driver.lowerExpr(
                cachedValue,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else if let syntheticLinks {
            let result = arena.appendTemporary(type: propType)
            emitNonThrowingCall(
                callee: interner.intern(syntheticLinks.load),
                arg: receiverID,
                result: result,
                into: &instructions
            )
            currentValue = result
        } else if isObjectOwned, !usesGetterAccessor, let propertySymbol {
            let storageSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            let result = arena.appendExpr(.symbolRef(storageSymbol), type: propType)
            instructions.append(.loadGlobal(result: result, symbol: storageSymbol))
            currentValue = wrapLateinitReadIfNeeded(
                result, symbol: propertySymbol, sema: sema, arena: arena, interner: interner,
                instructions: &instructions
            )
        } else if let propertySymbol,
                  let itableValue = tryLowerInterfaceItablePropertyGetterRead(
                      propertySymbol: propertySymbol,
                      loweredReceiverID: receiverID,
                      resultType: propType,
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &instructions
                  )
        {
            // Interface-typed receiver: the interface has no per-instance
            // storage, so read through the itable getter slot.
            currentValue = itableValue
        } else if let virtualGetterDispatch {
            let result = arena.appendTemporary(type: propType)
            let virtualAccessorArguments = propertyAccessorArguments(
                for: virtualGetterDispatch.accessorSymbol, arguments: [receiverID], callExprID: exprID,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            instructions.append(.virtualCall(
                symbol: virtualGetterDispatch.accessorSymbol,
                callee: interner.intern("get"),
                receiver: virtualAccessorArguments[0],
                arguments: Array(virtualAccessorArguments.dropFirst()),
                result: result,
                canThrow: false,
                dispatch: virtualGetterDispatch.dispatch
            ))
            currentValue = result
        } else if let enumHelperCallees {
            let result = arena.appendTemporary(type: propType)
            emitNonThrowingCall(
                callee: enumHelperCallees.getter,
                arg: receiverID,
                result: result,
                into: &instructions
            )
            currentValue = result
        } else if usesGetterAccessor, let propertySymbol {
            let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
            let result = arena.appendTemporary(type: propType)
            let getterArguments = propertyAccessorArguments(
                for: getterSymbol, arguments: [receiverID], callExprID: exprID,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            instructions.append(.call(
                symbol: getterSymbol,
                callee: interner.intern("get"),
                arguments: getterArguments,
                result: result,
                canThrow: false
            ))
            currentValue = result
        } else if let fieldOffset {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let result = arena.appendTemporary(type: propType)
            instructions.append(.call(
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverID, offsetExpr],
                result: result,
                canThrow: false
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
            emitNonThrowingCall(
                callee: getterName,
                arg: receiverID,
                result: result,
                into: &instructions
            )
            currentValue = result
        }

        // Kotlin reads the left-hand property before evaluating the RHS. The
        // RHS can call code that mutates this same property, so lowering it
        // before the load would make the compound operation use the new value.
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueType = arena.exprType(valueID)

        // `newValue == nil` means a Unit-returning `plusAssign`-style operator
        // already mutated the loaded value in place, so no store is needed —
        // mirrors bare-name compound assign's handling in ExprLowerer.
        let newValue: KIRExprID? = {
            if ast.arena.isIncrementDecrement(exprID),
               let callBinding = sema.bindings.callBindings[exprID],
               let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
               signature.receiverType != nil
            {
                let callResult = arena.appendTemporary(type: signature.returnType)
                // `++`/`--` invoke `inc()`/`dec()` with no explicit arguments,
                // so defaulted parameters must ride the `<name>$default` stub
                // just like an explicit `a.inc()` call.
                emitIncrementDecrementOperatorCall(
                    callBinding: callBinding,
                    operatorName: op == .plusAssign ? "inc" : "dec",
                    receiverArgument: currentValue,
                    callExprID: exprID,
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

            let bundledStringPlus = isBundledStringPlusCall(
                sema.bindings.callBindings[exprID],
                op: op,
                sema: sema,
                interner: interner
            )
            if !usesBuiltinStringCompound && !bundledStringPlus,
               let callBinding = sema.bindings.callBindings[exprID],
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
                let resolvedMemberName = sema.symbols.symbol(callBinding.chosenCallee)
                    .map { interner.resolve($0.name) }
                    ?? interner.resolve(loweredCalleeName)
                if emitRuntimeBackedCollectionMemberCallIfNeeded(
                    memberName: resolvedMemberName,
                    receiverType: propType,
                    chosenCallee: callBinding.chosenCallee,
                    arguments: finalArguments,
                    result: callResult,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) {
                    return returnType == sema.types.unitType ? nil : callResult
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false
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
            let isStringCompound = op == .plusAssign
                && (propType == stringType || propType == nullableStringType
                    || valueType == stringType || valueType == nullableStringType)
            if !isStringCompound {
                let result = arena.appendTemporary(type: propType)
                instructions.append(.binary(op: kirOp, lhs: currentValue, rhs: valueID, result: result))
                return SmallIntegerWrap.append(
                    result, type: propType, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                ) ?? result
            }
            // Kotlin's `String += Any?` calls toString() on a non-String operand
            // (Kotlin's String.plus(other: Any?)); a non-String currentValue/valueID
            // must be converted the same way `+`/string-template concatenation does
            // (CallLowerer.emitAnyToStringWithNullGuard) before reaching
            // __kk_string_concat_flat, which assumes both arguments are already
            // flat String aggregates -- feeding it a raw boxed value (e.g. a class
            // instance, or an unboxed Int/Boolean) reads it as one, silently
            // dropping/mis-rendering the value or crashing.
            let effectiveCurrent: KIRExprID = if propType == stringType {
                currentValue
            } else {
                emitAnyToStringWithNullGuard(
                    valueID: currentValue,
                    valueType: propType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            let effectiveValue: KIRExprID = if valueType == stringType {
                valueID
            } else {
                emitAnyToStringWithNullGuard(
                    valueID: valueID,
                    valueType: valueType ?? sema.types.anyType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            let result = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                callee: interner.intern("__kk_string_concat_flat"),
                arguments: [effectiveCurrent, effectiveValue],
                result: result,
                canThrow: false
            ))
            return result
        }()

        if let newValue {
            if let syntheticLinks {
                instructions.append(.call(
                    callee: interner.intern(syntheticLinks.store),
                    arguments: [receiverID, newValue],
                    result: nil,
                    canThrow: false
                ))
            } else if isObjectOwned, !storeUsesSetterAccessor, let propertySymbol {
                if let backingField = sema.symbols.backingFieldSymbol(for: propertySymbol) {
                    let storedValue = normalizedValueForNullablePrimitiveSlot(
                        newValue,
                        slotType: sema.symbols.propertyType(for: backingField) ?? propType,
                        types: sema.types,
                        arena: arena,
                        into: &instructions
                    )
                    instructions.append(.storeGlobal(value: storedValue, symbol: backingField))
                } else {
                    let globalRef = arena.appendExpr(.symbolRef(propertySymbol), type: propType)
                    instructions.append(.constValue(result: globalRef, value: .symbolRef(propertySymbol)))
                    instructions.append(.copy(from: newValue, to: globalRef))
                }
            } else if let propertySymbol,
                      tryLowerInterfaceItablePropertySetterWrite(
                          propertySymbol: propertySymbol,
                          loweredReceiverID: receiverID,
                          loweredValueID: newValue,
                          sema: sema,
                          cache: driver.ctx.nominalDispatchCache,
                          arena: arena,
                          interner: interner,
                          instructions: &instructions
                      ) != nil
            {
                // Interface-typed receiver: write through the itable setter
                // slot (the helper already emitted the call).
            } else if let virtualSetterDispatch {
                let setterResult = arena.appendTemporary(type: sema.types.unitType)
                let setterValueID = propertySymbol.map {
                    erasedVirtualSetterValue(
                        newValue, propertySymbol: $0,
                        sema: sema, arena: arena, interner: interner, instructions: &instructions
                    )
                } ?? newValue
                let virtualAccessorArguments = propertyAccessorArguments(
                    for: virtualSetterDispatch.accessorSymbol, arguments: [receiverID, setterValueID], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.virtualCall(
                    symbol: virtualSetterDispatch.accessorSymbol,
                    callee: interner.intern("set"),
                    receiver: virtualAccessorArguments[0],
                    arguments: Array(virtualAccessorArguments.dropFirst()),
                    result: setterResult,
                    canThrow: false,
                    dispatch: virtualSetterDispatch.dispatch
                ))
            } else if let enumHelperCallees {
                instructions.append(.call(
                    callee: enumHelperCallees.setter,
                    arguments: [receiverID, newValue],
                    result: arena.appendTemporary(type: sema.types.unitType),
                    canThrow: false
                ))
            } else if usesSetterAccessor, let propertySymbol {
                let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                    ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
                let setterResult = arena.appendTemporary(type: sema.types.unitType)
                let setterArguments = propertyAccessorArguments(
                    for: setterSymbol, arguments: [receiverID, newValue], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.call(
                    symbol: setterSymbol,
                    callee: interner.intern("set"),
                    arguments: setterArguments,
                    result: setterResult,
                    canThrow: false
                ))
            } else if let fieldOffset {
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                let storedValue = normalizedValueForNullablePrimitiveSlot(
                    newValue,
                    slotType: propType,
                    types: sema.types,
                    arena: arena,
                    into: &instructions
                )
                instructions.append(.call(
                    callee: interner.intern("kk_array_set"),
                    arguments: [receiverID, offsetExpr, storedValue],
                    result: nil,
                    canThrow: false
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
                instructions.append(.call(callee: setterName, arguments: [receiverID, newValue], result: setterResult, canThrow: false))
            }
            if ast.arena.incrementDecrementReturnsValue(exprID) {
                return newValue
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// The setter placeholder for a stored member property of an enum class
    /// (see `KIRLoweringDriver+EnumEntryStorage.swift`), or `nil` when the
    /// property is not enum-owned or is written through its own accessor.
    func enumPropertySetterPlaceholder(
        for propertySymbol: SymbolID,
        allowValInitialization: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard let info = sema.symbols.symbol(propertySymbol),
              info.kind == .property,
              info.flags.contains(.mutable) || allowValInitialization,
              let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              sema.symbols.symbol(ownerSymbol)?.kind == .enumClass
        else {
            return nil
        }
        return EnumPropertyHelperNames.placeholder(
            prefix: EnumPropertyHelperNames.setterPrefix,
            ownerSymbol: ownerSymbol,
            propertyName: info.name,
            interner: interner
        )
    }

    func enumPropertyGetterPlaceholder(
        for propertySymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard let info = sema.symbols.symbol(propertySymbol),
              info.kind == .property,
              // Enum-class statics (the synthetic `Enum.entries` stub) have
              // no per-entry storage to read through the placeholder helper
              // (KUU-3544).
              !info.flags.contains(.static),
              let ownerSymbol = enumClassOwnerSymbol(forProperty: propertySymbol, sema: sema)
        else {
            return nil
        }
        return EnumPropertyHelperNames.placeholder(
            prefix: EnumPropertyHelperNames.getterPrefix,
            ownerSymbol: ownerSymbol,
            propertyName: info.name,
            interner: interner
        )
    }

    func enumClassOwnerSymbol(forProperty propertySymbol: SymbolID, sema: SemaModule) -> SymbolID? {
        guard let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol) else { return nil }
        if sema.symbols.symbol(ownerSymbol)?.kind == .enumClass {
            return ownerSymbol
        }
        return enumClassOwnerSymbol(forEntryField: ownerSymbol, sema: sema)
    }

    func memberPropertyUsesSetterAccessor(
        _ propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        // Imported member properties have no accessor AST. Their metadata
        // registers the setter that must also observe bare receiver-DSL writes.
        // Backing-field symbols stay on the storage path inside the setter.
        if let property = sema.symbols.symbol(propertySymbol),
           property.kind == .property, property.flags.contains(.importedLibrary),
           let setter = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol),
           let linkName = sema.symbols.externalLinkName(for: setter), !linkName.isEmpty
        {
            return true
        }
        // CLASS-008: a synthetic forwarding property for `by` delegation has
        // no `.propertyDecl` AST node for the loop below to find — its setter
        // writes through the delegate field, not a real backing field.
        if sema.symbols.classDelegationForwardingPropertyInfo(for: propertySymbol) != nil {
            return true
        }
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            // KUU-2943, KUU-2946: a delegated `var` always writes through the
            // synthesized setValue-forwarding setter accessor, so it must
            // win this check before the setter-body test. A bare
            // `private set`/`protected set` clause records only a
            // visibility restriction — its `.unit` body would otherwise
            // downgrade the write to direct field storage, which lands on
            // a dead slot since the property has no backing field.
            if propertyDecl.delegateExpression != nil {
                return true
            }
            if let setter = propertyDecl.setter {
                return setter.body != .unit
            }
            return false
        }
        return false
    }

    /// Write counterpart of `tryLowerInterfaceItablePropertyGetterRead`
    /// (`CallLowerer+MemberPropertyReads.swift`, BUG-141): an interface has
    /// no per-instance storage of its own, so a stored/abstract `var`
    /// written through an interface-typed receiver cannot use a concrete
    /// field offset either. Dispatch through the interface's itable to the
    /// implementing type's setter, mirroring the read side.
    func tryLowerInterfaceItablePropertySetterWrite(
        propertySymbol: SymbolID,
        loweredReceiverID: KIRExprID,
        loweredValueID: KIRExprID,
        sema: SemaModule,
        cache: KIRNominalDispatchCache,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let propertyInfo = sema.symbols.symbol(propertySymbol),
              let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .interface,
              (propertyInfo.declSite != nil
                  || propertyInfo.flags.contains(.importedLibrary)),
              let methodSlot = kirInterfacePropertySetterSlot(
                  interfaceProperty: propertySymbol,
                  interfaceSymbol: ownerSymbol,
                  sema: sema,
                  interner: interner,
                  cache: cache
              )
        else {
            return nil
        }
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: ownerSymbol, sema: sema, interner: interner
        )
        let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        let result = arena.appendTemporary(type: sema.types.unitType)
        instructions.append(.virtualCall(
            symbol: setterSymbol,
            callee: interner.intern("set"),
            receiver: loweredReceiverID,
            arguments: [loweredValueID],
            result: result,
            canThrow: false,
            dispatch: .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
