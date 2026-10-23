// swiftlint:disable file_length

extension ExprLowerer {
    func lowerNameRefExpr(
        name: InternedString,
        exprID: ExprID,
        boundType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let thisID = interner.intern("this")
        // Receiver-function lambdas can bind implicit `it` to a semantic
        // parameter symbol that differs from the synthetic KIR parameter
        // symbol. Inlined lambdas that do not register their own params
        // still resolve an outer `it` through its semantic symbol.
        if let paramSymbol = driver.ctx.lambdaParamSymbol(named: name),
           sema.bindings.identifierSymbols[exprID].map({
               guard $0 != paramSymbol,
                     let boundValue = driver.ctx.localValue(for: $0),
                     let boundType,
                     let boundValueType = arena.exprType(boundValue)
               else { return true }
               return boundValueType != boundType
           }) ?? true,
           let localValue = driver.ctx.localValue(for: paramSymbol)
        {
            return driver.callLowerer.materializeSmartcastedPrimitiveValue(
                localValue, boundType: boundType, sema: sema, arena: arena,
                instructions: &instructions
            ) ?? localValue
        }
        if name == thisID,
           let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
        {
            return receiverExprID
        }
        // The master launcher lowering can now bind a receiver value, but
        // kk_coroutine_current_scope still returns an opaque runtime handle.
        // Its CoroutineScope context must use the ambient context bridge.
        let hasRuntimeScopeReceiver = driver.ctx.activeImplicitReceiverExprID().map {
            driver.ctx.runtimeCoroutineScopeReceiverExprIDs.contains($0)
        } ?? false
        if sema.bindings.implicitReceiverMemberNames[exprID] != nil,
           (driver.ctx.activeImplicitReceiverExprID() == nil || hasRuntimeScopeReceiver),
           let symbol = sema.bindings.identifierSymbols[exprID],
           sema.symbols.symbol(symbol)?.fqName == [
               interner.intern("kotlinx"), interner.intern("coroutines"),
               interner.intern("CoroutineScope"), interner.intern("coroutineContext"),
           ]
        {
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_coroutine_current_context"),
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        // BUG-B/BUG-C: an enum value has no stored-field object layout
        // (its KIR representation is a raw ordinal Int, only boxed for
        // Any-erased contexts), so an implicit-receiver read of its
        // built-in `name`/`ordinal` properties or of a constructor
        // property falls through every `.class`/`.interface`-owner
        // branch below and lands on the generic symbol-reference
        // fallback near the end of this case -- silently wrong (reads an
        // unwritten slot as 0) for an Int-typed property, and a SIGSEGV
        // once codegen treats the bogus "pointer" as a String for a
        // String-typed one. Mirror the explicit-receiver handling
        // (`tryLowerEnumEntryPropertyRead` / the enum branch of
        // `lowerStoredMemberPropertyReadValue` in
        // CallLowerer+MemberPropertyReads.swift) here, before any of
        // those generic branches can intercept the read.
        if let symbol = sema.bindings.identifierSymbols[exprID]
            ?? sema.bindings.callBindings[exprID]?.chosenCallee,
           let symInfo = sema.symbols.symbol(symbol),
           symInfo.kind == .property,
           symInfo.name == interner.intern("name") || symInfo.name == interner.intern("ordinal"),
           let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
           let receiverType = arena.exprType(receiverExprID),
           let (_, receiverClassSym) = resolveClassTypeSymbol(
               sema.types.makeNonNullable(receiverType), sema: sema
           ),
           receiverClassSym.kind == .enumClass
        {
            let resultType = boundType ?? sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
            if symInfo.name == interner.intern("ordinal") {
                return emitNonThrowingCall(
                    callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
                    arg: receiverExprID,
                    resultType: resultType,
                    arena: arena,
                    into: &instructions
                )
            }
            let result = arena.appendTemporary(type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: symInfo.name,
                arguments: [receiverExprID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if let symbol = sema.bindings.identifierSymbols[exprID]
            ?? sema.bindings.callBindings[exprID]?.chosenCallee,
           let symInfo = sema.symbols.symbol(symbol),
           // `.field` is deliberately excluded: a bare reference to an
           // enum *entry* itself (e.g. `NORTH` inside the companion
           // object's `when (direction) { NORTH -> SOUTH; ... }`) also
           // resolves to a `.field` symbol parented by the enum class,
           // but it names a global entry constant, not an instance
           // property -- routing it through the constructor-property
           // placeholder below produced an unresolved
           // `$enumConstructorProperty$<id>$NORTH` call.
           symInfo.kind == .property,
           let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
           sema.symbols.symbol(ownerSymbol)?.kind == .enumClass,
           let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
        {
            let resultType = boundType ?? sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
            let result = arena.appendTemporary(type: resultType)
            if driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema) {
                let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                driver.callLowerer.appendPropertyGetterCall(
                    getterSymbol: getterSymbol,
                    receiver: receiverExprID,
                    callExprID: exprID,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            let helperName = interner.intern(
                "$enumConstructorProperty$\(ownerSymbol.rawValue)$\(interner.resolve(symInfo.name))"
            )
            instructions.append(.call(
                symbol: nil,
                callee: helperName,
                arguments: [receiverExprID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        // Enum-entry properties are owned by their entry field in Sema, but
        // use the containing enum's ordinal-keyed side storage at runtime.
        if let symbol = sema.bindings.identifierSymbols[exprID]
                ?? sema.bindings.callBindings[exprID]?.chosenCallee,
           let propertyInfo = sema.symbols.symbol(symbol),
           propertyInfo.kind == .property,
           let entryField = sema.symbols.parentSymbol(for: symbol),
           let enumOwnerSymbol = driver.callLowerer.enumClassOwnerSymbol(forEntryField: entryField, sema: sema),
           let activeReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
        {
            let receiverExprID: KIRExprID
            // An inner class stores its enclosing enum instance in `$outer`;
            // enum-entry properties must dispatch on that ordinal value,
            // not on the inner object currently being initialized.
            var outerInstructions: [KIRInstruction] = []
            if let outerReceiver = resolveOuterChainValue(
                from: activeReceiverExprID,
                to: enumOwnerSymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &outerInstructions
            ) {
                instructions.append(contentsOf: outerInstructions)
                receiverExprID = outerReceiver
            } else if let capturedReceiver = driver.ctx.capturedOuterReceiverExprID(
                for: enumOwnerSymbol
            ) ?? driver.ctx.capturedOuterReceiverExprID(
                reaching: enumOwnerSymbol,
                sema: sema
            ) {
                // Object literals register the construction-site receiver as a
                // captured outer receiver for the enclosing class. Enum entries
                // must keep dispatching on that value while the anonymous object
                // is the active implicit receiver.
                receiverExprID = capturedReceiver
            } else if let receiverSymbol = sema.bindings.implicitReceiverOuterReceiver(for: exprID),
                      let capturedReceiver = driver.ctx.localValue(for: receiverSymbol)
            {
                receiverExprID = capturedReceiver
            } else {
                receiverExprID = activeReceiverExprID
            }
            let resultType = boundType ?? sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
            let result = arena.appendTemporary(type: resultType)
            if driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema) {
                let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                driver.callLowerer.appendPropertyGetterCall(
                    getterSymbol: getterSymbol,
                    receiver: receiverExprID,
                    callExprID: exprID,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            if let getterPlaceholder = driver.callLowerer.enumPropertyGetterPlaceholder(
                for: symbol, sema: sema, interner: interner
            ) {
                instructions.append(.call(
                    symbol: nil,
                    callee: getterPlaceholder,
                    arguments: [receiverExprID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        if let memberName = sema.bindings.implicitReceiverMemberNames[exprID],
           let activeReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
        {
            // KSP-CAP-001: an enclosing immutable property captured by an
            // object-literal member function is restored as a local value.
            // It must take precedence over the implicit receiver member
            // path, which would otherwise apply the enclosing property's
            // field offset to the object literal receiver.
            if let symbol = sema.bindings.identifierSymbols[exprID],
               sema.symbols.symbol(symbol)?.kind == .property,
               !driver.ctx.isMutableCaptureBoxed(symbol),
               let localValue = driver.ctx.localValue(for: symbol)
            {
                return driver.callLowerer.materializeSmartcastedPrimitiveValue(
                    localValue, boundType: boundType, sema: sema, arena: arena,
                    instructions: &instructions
                ) ?? localValue
            }
            let receiverExprID: KIRExprID
            if let symbol = sema.bindings.identifierSymbols[exprID],
               let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: symbol),
               let activeReceiver = driver.ctx.activeImplicitReceiverExprID(),
               let activeReceiverType = arena.exprType(activeReceiver),
               sema.types.isSubtype(
                   sema.types.makeNonNullable(activeReceiverType),
                   sema.types.makeNonNullable(extensionReceiverType)
               )
            {
                // Member extension property references have two implicit
                // receivers. The outer-receiver binding names the dispatch
                // receiver; the active receiver supplies the extension value.
                receiverExprID = activeReceiver
            } else if let receiverSymbol = sema.bindings.implicitReceiverOuterReceiver(for: exprID),
               let capturedReceiver = driver.ctx.localValue(for: receiverSymbol)
            {
                receiverExprID = capturedReceiver
            } else if let symbol = sema.bindings.identifierSymbols[exprID],
               let capturedReceiver = driver.objectLiteralLowerer.implicitReceiverExprID(
                   forProperty: symbol,
                   sema: sema,
                   arena: arena
               )
            {
                receiverExprID = capturedReceiver
            } else {
                receiverExprID = activeReceiverExprID
            }
            let receiverType = arena.exprType(receiverExprID) ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let memberStr = interner.resolve(memberName)
            let resultType = boundType ?? sema.types.anyType
            let result = arena.appendTemporary(type: resultType
            )
            // KUU-1451: bundled "property-style" members are modelled as
            // zero-argument extension functions (`List.lastIndex`,
            // `List.indices`, `Array.lastIndex`, ...). Sema records such a
            // bare read as a call binding plus `implicitReceiverMemberNames`
            // rather than a `.property` identifier symbol, so emit the call
            // with the implicit receiver as the callee's first argument —
            // matching the explicit `receiver.lastIndex` member-call shape.
            if let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
               let calleeSymbol = sema.symbols.symbol(chosenCallee),
               calleeSymbol.kind == .function,
               sema.symbols.functionSignature(for: chosenCallee)?.receiverType != nil
            {
                let loweredCallee: InternedString = if let linkName = sema.symbols.externalLinkName(for: chosenCallee),
                                                       !linkName.isEmpty
                {
                    interner.intern(linkName)
                } else {
                    calleeSymbol.name
                }
                // Facade callees are package-level extension functions —
                // statically dispatched with the implicit receiver as the
                // first argument.
                instructions.append(.call(
                    symbol: chosenCallee,
                    callee: loweredCallee,
                    arguments: [receiverExprID],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
            if let enumProperty = driver.callLowerer.tryLowerEnumBasePropertyRead(
                propertySymbol: sema.bindings.identifierSymbols[exprID]
                    ?? sema.bindings.callBindings[exprID]?.chosenCallee,
                receiver: receiverExprID, receiverType: receiverType,
                resultType: resultType,
                sema: sema, arena: arena, interner: interner,
                instructions: &instructions
            ) {
                return enumProperty
            }
            // Enum entry body functions use the enum value itself as
            // their implicit receiver. Its runtime representation is the
            // entry ordinal, so the synthetic Enum.name property cannot
            // be read as an ordinary stored property on that receiver.
            // Route it through the same enum-name rewrite used for
            // explicit receiver reads; ordinal is already the boxed
            // receiver's integer payload.
            if (memberStr == "name" || memberStr == "ordinal"),
               let (_, receiverClass) = resolveClassTypeSymbol(
                   nonNullReceiverType,
                   sema: sema
               ),
               receiverClass.kind == .enumClass
            {
                if memberStr == "ordinal" {
                    emitNonThrowingCall(
                        callee: interner.intern("kk_unbox_int"),
                        arg: receiverExprID,
                        result: result,
                        into: &instructions
                    )
                } else {
                    instructions.append(.call(
                        symbol: nil,
                        callee: memberName,
                        arguments: [receiverExprID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
            if memberStr == "code", nonNullReceiverType == sema.types.charType {
                emitNonThrowingCall(
                    callee: interner.intern("kk_char_code"),
                    arg: receiverExprID,
                    result: result,
                    into: &instructions
                )
                return result
            }

            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                if memberStr == "length" {
                    emitNonThrowingCall(
                        callee: interner.intern("__kk_string_struct_get_length"),
                        arg: receiverExprID,
                        result: result,
                        into: &instructions
                    )
                    return result
                }
            }

            // Collection properties: size, isEmpty. Restricted to receivers
            // that are collections (or of unknown class), so that a user
            // class declaring its own `size`/`isEmpty` member keeps its
            // declared accessor / backing field on implicit-receiver reads.
            let receiverMayBeCollection = resolveClassTypeSymbol(nonNullReceiverType, sema: sema)
                .map { KnownCompilerNames(interner: interner).isCollectionLikeSymbol($0.symbol) }
                ?? true
            // Abstract class properties have no usable declaration-local
            // field value. Resolve them through the class vtable before
            // collection shortcuts or the stored-field fallback below.
            if let propertySymbol = sema.bindings.identifierSymbols[exprID],
               let (accessorSymbol, dispatch) = driver.callLowerer.tryResolvePropertyAccessorVirtualDispatch(
                   propertySymbol: propertySymbol,
                   receiverExpr: exprID,
                   accessorKind: .getter,
                   ast: ast,
                   sema: sema,
                   interner: interner
               )
            {
                let virtualAccessorArguments = driver.callLowerer.propertyAccessorArguments(
                    for: accessorSymbol, arguments: [receiverExprID], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.virtualCall(
                    symbol: accessorSymbol,
                    callee: interner.intern("get"),
                    receiver: virtualAccessorArguments[0],
                    arguments: Array(virtualAccessorArguments.dropFirst()),
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatch
                ))
                return result
            }

            // A user-declared member with a custom getter shadows the built-in
            // collection shortcuts below: `size` / `isEmpty` inside a class that
            // declares them must run its own getter, not kk_collection_size.
            let implicitMemberUsesAccessor: Bool = {
                guard let symbol = sema.bindings.identifierSymbols[exprID],
                      let sym = sema.symbols.symbol(symbol),
                      sym.kind == .property,
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                      let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
                      ownerKind == .class || ownerKind == .interface
                else {
                    return false
                }
                return driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
            }()

            // Arrays have their own storage ABI and are not Collection handles.
            // Implicit `size` reads in extension bodies must use the same
            // array primitive as an explicit `this.size` read.
            if memberStr == "size", !implicitMemberUsesAccessor,
               ReceiverClassifier(sema: sema, interner: interner).isArrayLikeType(nonNullReceiverType)
            {
                emitNonThrowingCall(
                    callee: interner.intern("__kk_array_size"),
                    arg: receiverExprID,
                    result: result,
                    into: &instructions
                )
                return result
            }

            if receiverMayBeCollection, memberStr == "size", !implicitMemberUsesAccessor {
                emitNonThrowingCall(
                    callee: interner.intern("__kk_collection_size"),
                    arg: receiverExprID,
                    result: result,
                    into: &instructions
                )
                return result
            }
            if receiverMayBeCollection, memberStr == "isEmpty", !implicitMemberUsesAccessor {
                emitNonThrowingCall(
                    callee: interner.intern("__kk_collection_isEmpty"),
                    arg: receiverExprID,
                    result: result,
                    into: &instructions
                )
                return result
            }

            // Some implicit member expressions carry their selected
            // property only in the call binding. Preserve the same
            // abstract/open class dispatch in that representation too.
            if let symbol = sema.bindings.identifierSymbols[exprID]
                ?? sema.bindings.callBindings[exprID]?.chosenCallee,
               let propertyInfo = sema.symbols.symbol(symbol),
               propertyInfo.kind == .property,
               propertyInfo.flags.contains(.abstractType)
                   || propertyInfo.flags.contains(.openType),
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               let ownerInfo = sema.symbols.symbol(ownerSymbol),
               ownerInfo.kind == .class,
               !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty,
               let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                   SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
               ]
            {
                let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                driver.callLowerer.appendVirtualPropertyGetterCall(
                    getterSymbol: getterSymbol,
                    getterSlot: getterSlot,
                    receiver: receiverExprID,
                    callExprID: exprID,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }

            // KSP-CAP-018: a computed object-literal property has no
            // instance field anyone writes, so reading it through the
            // implicit receiver has to call its `get` accessor — this path
            // used to fall straight through to the field load below and
            // return the zeroed slot. The explicit-receiver read
            // (`tryLowerObjectLiteralStoredPropertyRead`) already did this;
            // both now share one predicate so they cannot disagree about
            // whether an accessor exists to call.
            if let symbol = sema.bindings.identifierSymbols[exprID],
               sema.bindings.isObjectLiteralPropertySymbol(symbol),
               driver.callLowerer.objectLiteralPropertyUsesAccessor(symbol, ast: ast, sema: sema)
            {
                instructions.append(.call(
                    symbol: symbol,
                    callee: interner.intern("get"),
                    arguments: [receiverExprID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }

            if let symbol = sema.bindings.identifierSymbols[exprID],
               sema.bindings.isObjectLiteralPropertySymbol(symbol),
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[symbol]
            {
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
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [fieldReceiverExprID, offsetExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return wrapLateinitReadIfNeeded(
                    result,
                    symbol: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }

            if let symbol = sema.bindings.identifierSymbols[exprID],
               let sym = sema.symbols.symbol(symbol),
               sym.kind == .property,
               let externalLinkName = sema.symbols.externalLinkName(for: symbol),
               !externalLinkName.isEmpty
            {
                instructions.append(.call(
                    symbol: symbol,
                    callee: interner.intern(externalLinkName),
                    arguments: [receiverExprID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }

            if let symbol = sema.bindings.identifierSymbols[exprID],
               let interfaceRead = driver.callLowerer.tryLowerInterfaceItablePropertyGetterRead(
                   propertySymbol: symbol,
                   loweredReceiverID: receiverExprID,
                   resultType: resultType,
                   sema: sema,
                   arena: arena,
                   interner: interner,
                   instructions: &instructions
               )
            {
                return interfaceRead
            }

            // KSP-928: implicit reads of abstract/open class properties
            // must dispatch through the class vtable. This is the path
            // used by AbstractMap's skeletal methods for `entries`.
            if let symbol = sema.bindings.identifierSymbols[exprID],
               let propertyInfo = sema.symbols.symbol(symbol),
               propertyInfo.kind == .property,
               propertyInfo.flags.contains(.abstractType)
                   || propertyInfo.flags.contains(.openType),
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               let ownerInfo = sema.symbols.symbol(ownerSymbol),
               ownerInfo.kind == .class,
               !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty,
               let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                   SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
               ]
            {
                let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                let virtualAccessorArguments = driver.callLowerer.propertyAccessorArguments(
                    for: getterSymbol, arguments: [receiverExprID], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.virtualCall(
                    symbol: getterSymbol,
                    callee: interner.intern("get"),
                    receiver: virtualAccessorArguments[0],
                    arguments: Array(virtualAccessorArguments.dropFirst()),
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: getterSlot)
                ))
                return result
            }

            // A custom getter must run for implicit-receiver reads just as
            // it does for an explicit `receiver.property` read.
            if let symbol = sema.bindings.identifierSymbols[exprID],
               let sym = sema.symbols.symbol(symbol),
               sym.kind == .property,
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
               ownerKind == .class || ownerKind == .interface,
               driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
            {
                let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                driver.callLowerer.appendPropertyGetterCall(
                    getterSymbol: getterSymbol,
                    receiver: receiverExprID,
                    callExprID: exprID,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }

            if let symbol = sema.bindings.identifierSymbols[exprID],
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               let ownerInfo = sema.symbols.symbol(ownerSymbol),
               ownerInfo.kind == .class || ownerInfo.kind == .interface,
               let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                   sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
               ]
            {
                // BUG-inner-outer: an inner class's implicit receiver is
                // its own instance, but a bare reference to a property
                // declared on an *enclosing* class must read through the
                // `$outer` chain instead -- otherwise this applies
                // `ownerSymbol`'s field offset to the wrong object,
                // aliasing whatever the inner class's own field happens
                // to occupy at that slot. A no-op (returns
                // `receiverExprID` unchanged) for every other case,
                // where the receiver already is (or subclasses)
                // `ownerSymbol`.
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
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [fieldReceiverExprID, offsetExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return wrapLateinitReadIfNeeded(
                    result,
                    symbol: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }

            if let symbol = sema.bindings.identifierSymbols[exprID],
               !driver.ctx.isMutableCaptureBoxed(symbol)
            {
                if let delegateValue = readLocalDelegateValue(
                    symbol: symbol, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                ) {
                    return delegateValue
                }
                if let localValue = driver.ctx.localValue(for: symbol) {
                    if let narrowed = driver.callLowerer.materializeSmartcastedPrimitiveValue(
                        localValue, boundType: boundType, sema: sema, arena: arena,
                        instructions: &instructions
                    ) {
                        return narrowed
                    }
                    return wrapLateinitReadIfNeeded(
                        localValue, symbol: symbol, sema: sema, arena: arena,
                        interner: interner, instructions: &instructions
                    )
                }
            }
        }
        if let boundIdentifierSymbol = sema.bindings.identifierSymbols[exprID] {
            // Unit uses the builtin value representation, including when
            // its public singleton symbol comes from bundled Kotlin source.
            if boundIdentifierSymbol == sema.types.unitClassSymbol {
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            // A bare `ClassName` value expression (not `ClassName.member()`,
            // which resolves through ordinary member lookup) that names a
            // class/interface/enum with a companion object is, per Kotlin's
            // own semantics, a reference to that companion object's
            // singleton instance -- the class symbol itself carries no
            // runtime value. Sema types this expression as the class's
            // nominal type (see ExprTypeChecker+NameLambdaAndCallableRefInference
            // .resolveTypeForCandidate) precisely so `ClassName.member()`
            // keeps resolving, but `identifierSymbols` still names the
            // class; redirect to the companion here so the branches below
            // (which key off `symbol.kind`) see the object, not the class.
            let symbol: SymbolID = {
                if let symInfo = sema.symbols.symbol(boundIdentifierSymbol),
                   symInfo.kind == .class || symInfo.kind == .interface || symInfo.kind == .enumClass,
                   let companionSymbol = sema.symbols.companionObjectSymbol(for: boundIdentifierSymbol)
                {
                    return companionSymbol
                }
                return boundIdentifierSymbol
            }()
            if driver.ctx.isMutableCaptureBoxed(symbol),
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
                if let narrowed = driver.callLowerer.materializeSmartcastedPrimitiveValue(
                    loadedValue, boundType: boundType, sema: sema, arena: arena,
                    instructions: &instructions
                ) {
                    return narrowed
                }
                return wrapLateinitReadIfNeeded(
                    loadedValue, symbol: symbol, sema: sema, arena: arena,
                    interner: interner, instructions: &instructions
                )
            }
            if let delegateValue = readLocalDelegateValue(
                symbol: symbol, sema: sema, arena: arena, interner: interner,
                instructions: &instructions
            ) {
                return driver.callLowerer.materializeSmartcastedPrimitiveValue(
                    delegateValue, boundType: boundType, sema: sema, arena: arena,
                    instructions: &instructions
                ) ?? delegateValue
            }
            if let localValue = driver.ctx.localValue(for: symbol) {
                // A smartcasted local keeps its declared (erased/boxed or
                // nullable) storage while the bound type narrows to a
                // non-null primitive — e.g. an `Any` slot holding a
                // RuntimeCharBox after `x is Char`. Materialize the unboxed
                // primitive here so every downstream consumer (conversion
                // callees, operator intrinsics, member calls) sees a raw
                // value, not the box handle.
                if let narrowed = driver.callLowerer.materializeSmartcastedPrimitiveValue(
                    localValue, boundType: boundType, sema: sema, arena: arena,
                    instructions: &instructions
                ) {
                    return narrowed
                }
                return wrapLateinitReadIfNeeded(
                    localValue, symbol: symbol, sema: sema, arena: arena,
                    interner: interner, instructions: &instructions
                )
            }
            // A bare companion/object property reference can resolve
            // directly to the property symbol without being marked as an
            // implicit-receiver member. Computed object properties still
            // have a one-parameter getter ABI, so materialize the singleton
            // receiver instead of leaving PropertyLoweringPass to emit a
            // zero-argument getter call.
            if let symInfo = sema.symbols.symbol(symbol),
               symInfo.kind == .property,
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               sema.symbols.symbol(ownerSymbol)?.kind == .object,
               driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema)
            {
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
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                driver.callLowerer.appendPropertyGetterCall(
                    getterSymbol: getterSymbol,
                    receiver: receiver,
                    callExprID: exprID,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            // Inline constant initializers only for immutable (val) properties.
            // Mutable (var) properties must always load from global store at runtime.
            if let symInfo = sema.symbols.symbol(symbol),
               let constant = propertyConstantInitializers[symbol] ?? sema.symbols.constValueExprKind(for: symbol),
               !symInfo.flags.contains(.mutable)
            {
                let id = arena.appendExpr(constant, type: boundType)
                instructions.append(.constValue(result: id, value: constant))
                return id
            }
            // Synthetic package/object properties backed by a runtime bridge
            // are read directly. Object getters retain their singleton receiver;
            // package getters (e.g. kotlinx.coroutines.isActive) take no receiver.
            let externalPropertyOwnerKind = sema.symbols.parentSymbol(for: symbol).flatMap {
                sema.symbols.symbol($0)?.kind
            }
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .property,
               sema.symbols.extensionPropertyReceiverType(for: symbol) == nil,
               externalPropertyOwnerKind == nil || externalPropertyOwnerKind == .package
                   || externalPropertyOwnerKind == .object,
               let externalLinkName = sema.symbols.externalLinkName(for: symbol),
               !externalLinkName.isEmpty
            {
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                let getterArguments = externalGlobalPropertyGetterArguments(
                    for: symbol, sema: sema, arena: arena, into: &instructions
                )
                instructions.append(.call(
                    symbol: symbol,
                    callee: interner.intern(externalLinkName),
                    arguments: getterArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // Native stub properties with externalLinkName: call native function
            // directly via the implicit receiver, bypassing field-offset dispatch.
            // (e.g. kk_duration_inWholeNanoseconds accessed inside a bundled
            // Kotlin source extension getter body.)
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .property,
               let externalLinkName = sema.symbols.externalLinkName(for: symbol),
               !externalLinkName.isEmpty,
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
            {
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    symbol: symbol,
                    callee: interner.intern(externalLinkName),
                    arguments: [receiverExprID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // Member property references inside class/object bodies must read
            // from the current implicit receiver instance rather than treating
            // the property symbol as a standalone value.
            //
            // Getter-only properties (`val size: Int get() = ...`) still occupy a
            // layout slot keyed by the property symbol, but that slot is never
            // written, so reading it here would yield garbage. Those dispatch to
            // the getter accessor in the branch below, matching the explicit
            // `this.size` path in CallLowerer+MemberPropertyReads.swift.
            //
            // KSP-CAP-001: a bare read of this kind resolved via plain scope
            // lookup rather than `resolveImplicitReceiverMember` (see
            // `inferNameRefExpr`), so it never set `implicitReceiverMemberNames`
            // and skipped the `implicitReceiverMemberNames` branch above, which is the only other
            // place that calls `implicitReceiverExprID(forProperty:)`. Without
            // it here too, an object-literal member function reading an
            // enclosing class's mutable property would use its own `this`
            // (`activeImplicitReceiverExprID`) with the enclosing class's field
            // offset -- the same wrong-receiver/offset mismatch PR #7186 fixed
            // for inner classes, but for object literals' bare mutable-property
            // reads. Mirror the write side (`.localAssign`'s field-offset branch
            // below), which already walks the captured outer-receiver chain.
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .property || sym.kind == .field || sym.kind == .backingField,
               let receiverExprID = driver.objectLiteralLowerer.implicitReceiverExprID(
                   forProperty: symbol,
                   sema: sema,
                   arena: arena
               ),
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
               ownerKind == .class || ownerKind == .interface,
               sym.kind != .property
                   || sema.symbols.backingFieldSymbol(for: symbol) != nil
                   || !driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema),
               let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                   sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
               ]
            {
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                // BUG-inner-outer: an inner class's implicit receiver is
                // its own instance, but a bare reference to a property
                // declared on an *enclosing* class must read through
                // the `$outer` chain instead of applying `ownerSymbol`'s
                // field offset to the wrong object. A no-op for every
                // other case, where the receiver already is (or
                // subclasses) `ownerSymbol`.
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
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [fieldReceiverExprID, offsetExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return wrapLateinitReadIfNeeded(
                    result,
                    symbol: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            // No direct field offset (the property has a distinct backing
            // field because it declares a custom accessor): dispatch to
            // the getter accessor when a real `get() { ... }` body exists
            // (mirrors CallLowerer+MemberPropertyReads.swift's explicit-
            // receiver equivalent), otherwise fall back to reading the
            // backing field's own storage directly, since the compiler-
            // provided default getter is just `return field` — the same
            // backing-field global that MemberLowerer+
            // DelegatedAndAccessorLowering.swift's lowerAccessorBody
            // resolves through the active receiver's instance layout.
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .property,
               let receiverExprID = driver.objectLiteralLowerer.implicitReceiverExprID(
                   forProperty: symbol,
                   sema: sema,
                   arena: arena
               ),
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
               let ownerKind = sema.symbols.symbol(ownerSymbol)?.kind,
               ownerKind == .class,
               !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty
            {
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                if let interfaceRead = driver.callLowerer.tryLowerInterfaceItablePropertyGetterRead(
                    propertySymbol: symbol,
                    loweredReceiverID: receiverExprID,
                    resultType: resultType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) {
                    return interfaceRead
                }
                // KSP-928: the abstract `entries` property in
                // AbstractMap is resolved from an implicit receiver in
                // its base-class methods, so use the subclass vtable
                // entry instead of the generated abstract getter stub.
                if let propertyInfo = sema.symbols.symbol(symbol),
                   propertyInfo.flags.contains(.abstractType)
                       || propertyInfo.flags.contains(.openType),
                   let getterSlot = sema.symbols.nominalLayout(for: ownerSymbol)?.vtableSlots[
                       SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                   ]
                {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    let result = arena.appendTemporary(type: resultType)
                    let virtualAccessorArguments = driver.callLowerer.propertyAccessorArguments(
                        for: getterSymbol, arguments: [receiverExprID], callExprID: exprID,
                        sema: sema, arena: arena, interner: interner, instructions: &instructions
                    )
                    instructions.append(.virtualCall(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        receiver: virtualAccessorArguments[0],
                        arguments: Array(virtualAccessorArguments.dropFirst()),
                        result: result,
                        canThrow: false,
                        thrownResult: nil,
                        dispatch: .vtable(slot: getterSlot)
                    ))
                    return result
                }
                if driver.callLowerer.memberPropertyUsesAccessor(symbol, ast: ast, sema: sema) {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
                    let result = arena.appendTemporary(type: resultType)
                    let getterArguments = driver.callLowerer.propertyAccessorArguments(
                        for: getterSymbol, arguments: [receiverExprID], callExprID: exprID,
                        sema: sema, arena: arena, interner: interner, instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: getterSymbol,
                        callee: interner.intern("get"),
                        arguments: getterArguments,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if let backingFieldSym = sema.symbols.backingFieldSymbol(for: symbol) {
                    let id = arena.appendExpr(.symbolRef(backingFieldSym), type: resultType)
                    instructions.append(.loadGlobal(result: id, symbol: backingFieldSym))
                    return wrapLateinitReadIfNeeded(
                        id,
                        symbol: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }
            }
            // Imported top-level properties with a custom getter have no
            // global slot in the producing artifact; their reads dispatch
            // to the precompiled getter accessor instead.
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .property,
               sema.symbols.propertyHasCustomGetter(for: symbol),
               sema.symbols.extensionPropertyReceiverType(for: symbol) == nil,
               let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol),
               {
                   let parentKind = sema.symbols.parentSymbol(for: symbol)
                       .flatMap { sema.symbols.symbol($0) }?.kind
                   return parentKind == nil || parentKind == .package
               }()
            {
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                let getterArguments = driver.callLowerer.propertyAccessorArguments(
                    for: getterSymbol, arguments: [], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.call(
                    symbol: getterSymbol,
                    callee: interner.intern("get"),
                    arguments: getterArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // A bare reference to an extension property inside a body whose
            // implicit receiver matches the extension receiver (e.g. `id`
            // inside another `Worker` extension body) must call the
            // property's getter on that receiver. Without this branch the
            // symbol falls through to `loadGlobal` below, which reads a
            // global slot that is never initialized (Int reads as 0,
            // String reads as null).
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .property,
               let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: symbol),
               let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol),
               let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
               let activeReceiverType = arena.exprType(receiverExprID),
               sema.types.isSubtype(
                   sema.types.makeNonNullable(activeReceiverType),
                   sema.types.makeNonNullable(extensionReceiverType)
               )
            {
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                let getterArguments = driver.callLowerer.propertyAccessorArguments(
                    for: getterSymbol, arguments: [receiverExprID], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.call(
                    symbol: getterSymbol,
                    callee: interner.intern("get"),
                    arguments: getterArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // Direct imports of singleton extension properties (such as
            // Int.Companion.MAX_VALUE) bind to a package-owned property.
            // Its storage is the getter, not a global slot; supply the
            // declared singleton receiver when no implicit receiver matched.
            if sema.symbols.symbol(symbol)?.kind == .property,
               let receiverType = sema.symbols.extensionPropertyReceiverType(for: symbol),
               case let .classType(receiverClass) = sema.types.kind(of: receiverType),
               sema.symbols.symbol(receiverClass.classSymbol)?.kind == .object,
               let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
            {
                let receiverSymbol = receiverClass.classSymbol
                driver.emitObjectLazyInitGuardIfNeeded(
                    objectSymbol: receiverSymbol, arena: arena, sema: sema,
                    interner: interner,
                    instructions: &instructions
                )
                let receiver = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                instructions.append(.constValue(result: receiver, value: .symbolRef(receiverSymbol)))
                let resultType = boundType
                    ?? sema.symbols.propertyType(for: symbol)
                    ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                let getterArguments = driver.callLowerer.propertyAccessorArguments(
                    for: getterSymbol, arguments: [receiver], callExprID: exprID,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                instructions.append(.call(
                    symbol: getterSymbol,
                    callee: interner.intern("get"),
                    arguments: getterArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .property || sym.kind == .field,
               {
                   let p = sema.symbols.parentSymbol(for: symbol)
                   let pk = p.flatMap { sema.symbols.symbol($0) }?.kind
                   return pk == nil || pk == .package || pk == .object
               }()
            {
                // BUG-274: this branch also covers a same-class-body
                // reference like `Companion.tag`, which Sema binds
                // directly to the property symbol -- collapsing the
                // "Companion" qualifier away entirely, unlike an
                // external `Comp.tag` access whose receiver still goes
                // through this function's class-name redirect and the
                // bare-object-reference fallback below (both guarded
                // there). Without this, that collapsing silently skips
                // the object's lazy clinit-equivalent.
                if let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   sema.symbols.symbol(ownerSymbol)?.kind == .object
                {
                    driver.emitObjectLazyInitGuardIfNeeded(
                        objectSymbol: ownerSymbol, arena: arena, sema: sema,
                        interner: interner,
                        instructions: &instructions
                    )
                }
                // A custom setter gives an object property a distinct backing
                // field. Its compiler-provided getter reads that field, so a
                // bare imported property reference must do the same.
                let storageSymbol: SymbolID
                if sym.kind == .property,
                   sema.symbols.parentSymbol(for: symbol).flatMap({ sema.symbols.symbol($0) })?.kind == .object,
                   let backingField = sema.symbols.backingFieldSymbol(for: symbol)
                {
                    storageSymbol = backingField
                } else {
                    storageSymbol = symbol
                }
                let id = arena.appendExpr(.symbolRef(storageSymbol), type: boundType)
                instructions.append(.loadGlobal(result: id, symbol: storageSymbol))
                return wrapLateinitReadIfNeeded(
                    id,
                    symbol: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            // Synthetic singleton objects with an externalLinkName (e.g.
            // kotlinx.coroutines.NonCancellable) resolve to a runtime handle via a
            // direct zero-argument call, bypassing the eager module-init allocation
            // used for real `object` declarations (which real objects need for their
            // own stored state, but a synthetic native-backed singleton doesn't).
            if let sym = sema.symbols.symbol(symbol),
               sym.kind == .object,
               let externalLinkName = sema.symbols.externalLinkName(for: symbol),
               !externalLinkName.isEmpty
            {
                let resultType = boundType ?? sema.symbols.propertyType(for: symbol) ?? sema.types.anyType
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    symbol: symbol,
                    callee: interner.intern(externalLinkName),
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // BUG-274: this is the generic bare-name fallback -- reached
            // for a real user `object`/`companion object` whenever it is
            // referenced as a value in its own right (an explicit-receiver
            // qualifier for a member call or property access, since
            // both `lowerMemberAssignExpr`/`lowerMemberCompoundAssignExpr`
            // and `CallLowerer`'s member-call dispatch lower the receiver
            // through here, or a plain value crossing an `Any`/interface
            // boundary). Trigger the object's lazy clinit-equivalent
            // before handing out its value, mirroring the JVM's
            // clinit-on-first-access trigger. A no-op for any symbol
            // that isn't a source-backed object (this compilation only
            // ever registers one for those; see `objectLazyInit`).
            if sema.symbols.symbol(symbol)?.kind == .object {
                driver.emitObjectLazyInitGuardIfNeeded(
                    objectSymbol: symbol, arena: arena, sema: sema,
                    interner: interner,
                    instructions: &instructions
                )
            }
            let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
            instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
            return id
        }
        let id = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
        instructions.append(.constValue(result: id, value: .unit))
        return id
    }
}
