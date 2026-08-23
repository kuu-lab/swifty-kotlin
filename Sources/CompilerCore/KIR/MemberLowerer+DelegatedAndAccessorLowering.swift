
extension MemberLowerer {
    func lowerMemberDecls(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext? = nil,
        isInterfaceContext: Bool = false
    ) -> (directMembers: [KIRDeclID], allDecls: [KIRDeclID]) {
        lowerMemberDecls(
            memberFunctions: memberFunctions,
            memberProperties: memberProperties,
            nestedClasses: nestedClasses,
            nestedObjects: nestedObjects,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            compilationCtx: compilationCtx,
            isInterfaceContext: isInterfaceContext
        )
    }

    func lowerDelegateAccessor(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        delegateStorageSymbol: SymbolID,
        delegateKind: StdlibDelegateKind,
        accessorKind: PropertyAccessorKind,
        shared: KIRLoweringSharedContext,
        allDecls: inout [KIRDeclID]
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        // See the matching note in MemberLowerer.lowerSingleMemberFunction
        // (KSP-CAP-001): this can run nested inside an enclosing function's
        // lowering (a delegated property on an object literal), so the reset
        // below must not discard that caller's scope.
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        var params: [KIRParameter] = []

        // Add receiver parameter if property has an owner class/object.
        if let ownerSymbol,
           let ownerSym = sema.symbols.symbol(ownerSymbol)
        {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            )
        }

        let returnType: TypeID
        let accessorName: InternedString
        let customGetValueSymbol = sema.symbols.delegateGetValueSymbol(for: propertySymbol)
        let customSetValueSymbol = sema.symbols.delegateSetValueSymbol(for: propertySymbol)
        let getValueName: InternedString = switch delegateKind {
        case .lazy:
            interner.intern("kk_lazy_get_value")
        case .observable:
            interner.intern("kk_observable_get_value")
        case .vetoable:
            interner.intern("kk_vetoable_get_value")
        case .notNull:
            interner.intern("kk_notNull_get_value")
        case .custom:
            // Dispatches via `symbol: customGetValueSymbol` below (a direct call to the
            // resolved user-defined operator), so this name is only used for KIR dumps/LLVM
            // instruction naming, never for runtime symbol lookup.
            interner.intern("getValue")
        }
        let setValueName: InternedString = switch delegateKind {
        case .lazy:
            interner.intern("setValue")
        case .observable:
            interner.intern("kk_observable_set_value")
        case .vetoable:
            interner.intern("kk_vetoable_set_value")
        case .notNull:
            interner.intern("kk_notNull_set_value")
        case .custom:
            interner.intern("setValue")
        }

        var body: KIRLoweringEmitContext = [.beginBlock]
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }

        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")

            let delegateHandleExprID = loadDelegateHandle(
                delegateStorageSymbol: delegateStorageSymbol,
                ownerSymbol: ownerSymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                body: &body
            )
            // call: $delegate_x.getValue(thisRef, kProperty) -> PropertyType
            let resultExprID = arena.appendTemporary(type: propertyType
            )
            let notNullThrows = delegateKind == .notNull
            let thrownExprID: KIRExprID? = notNullThrows
                ? arena.appendTemporary(type: sema.types.nullableAnyType
                )
                : nil
            body.append(
                .call(
                    symbol: delegateKind == .custom ? customGetValueSymbol : delegateStorageSymbol,
                    callee: getValueName,
                    arguments: delegateKind == .custom ? [delegateHandleExprID] + buildCustomDelegateGetterArgs(
                        propertySymbol: propertySymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        body: &body
                    ) : [delegateHandleExprID],
                    result: resultExprID,
                    canThrow: notNullThrows,
                    thrownResult: thrownExprID
                )
            )
            body.append(.returnValue(resultExprID))

        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")

            let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))

            // call: $delegate_x.setValue(thisRef, kProperty, value)
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            body.append(.constValue(result: valueExprID, value: .symbolRef(valueParamSymbol)))
            let delegateHandleExprID = loadDelegateHandle(
                delegateStorageSymbol: delegateStorageSymbol,
                ownerSymbol: ownerSymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                body: &body
            )
            let resultExprID = arena.appendTemporary(type: sema.types.unitType
            )
            body.append(
                .call(
                    symbol: delegateKind == .custom ? customSetValueSymbol : delegateStorageSymbol,
                    callee: setValueName,
                    arguments: delegateKind == .custom ? [delegateHandleExprID] + buildCustomDelegateSetterArgs(
                        propertySymbol: propertySymbol,
                        valueExprID: valueExprID,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        body: &body
                    ) : [delegateHandleExprID, valueExprID],
                    result: resultExprID,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            body.append(.returnUnit)
        }
        body.append(.endBlock)

        let syntheticAccessorSymbol = SyntheticSymbolScheme.propertyAccessorSymbol(
            for: propertySymbol,
            kind: accessorKind
        )

        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: syntheticAccessorSymbol,
                    name: accessorName,
                    params: params,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.clearImplicitReceiver()
    }

    /// DEBT-KIR-008: reads the delegate handle (the `Lazy`/`ObservableProperty`/
    /// custom-delegate instance stored in `$delegate_x`) for the current access.
    ///
    /// Class/interface instance delegates live inside the heap-allocated object,
    /// not in a module-global slot, so the read must go through
    /// `kk_array_get_inbounds` at the field's computed offset — mirroring
    /// `tryLowerStoredMemberPropertyRead` (regular stored-property reads) and
    /// `emitFieldStore` (writes, used by the matching constructor initializer).
    /// Falls back to `.loadGlobal` for top-level and `object`-member delegates,
    /// which intentionally keep a single shared instance backed by a real global.
    private func loadDelegateHandle(
        delegateStorageSymbol: SymbolID,
        ownerSymbol: SymbolID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let delegateType = sema.types.anyType
        if let ownerSymbol,
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface,
           let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[delegateStorageSymbol],
           let receiverExprID = driver.ctx.activeImplicitReceiverExprID()
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let result = arena.appendTemporary(type: delegateType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExprID, offsetExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let result = arena.appendTemporary(type: delegateType)
        body.append(.loadGlobal(result: result, symbol: delegateStorageSymbol))
        return result
    }

    private func buildCustomDelegateGetterArgs(
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        let thisRefExprID: KIRExprID
        if let receiver = driver.ctx.activeImplicitReceiverExprID() {
            thisRefExprID = receiver
        } else {
            thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: thisRefExprID, value: .null))
        }
        let kPropertyExprID = buildKPropertyStub(
            propertySymbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )
        return [thisRefExprID, kPropertyExprID]
    }

    private func buildCustomDelegateSetterArgs(
        propertySymbol: SymbolID,
        valueExprID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        buildCustomDelegateGetterArgs(
            propertySymbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        ) + [valueExprID]
    }

    /// Builds `(thisRef, kProperty)` args for a **local** delegated declaration's
    /// getValue/setValue call (`fun f() { val x by Prop() }`). Unlike a member
    /// delegate, whose `thisRef` is the enclosing instance, a local delegate is
    /// never bound to a receiver — `thisRef` is always `null` regardless of
    /// whether the declaration happens to sit inside a member function (where
    /// an unrelated implicit receiver for the *enclosing class* may be active).
    ///
    /// Takes a plain `[KIRInstruction]` (rather than `KIRLoweringEmitContext`,
    /// as `buildKPropertyStub` below does) because callers here are inlining
    /// into an *already-existing* function body being lowered by `ExprLowerer`,
    /// not building a standalone synthetic accessor function from scratch.
    func buildLocalDelegateAccessorArgs(
        localSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        instructions.append(.constValue(result: thisRefExprID, value: .null))
        var body = KIRLoweringEmitContext(instructions)
        let kPropertyExprID = buildKPropertyStub(
            propertySymbol: localSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )
        instructions = body.instructions
        return [thisRefExprID, kPropertyExprID]
    }

    private func buildKPropertyStub(
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let propertyName = sema.symbols.symbol(propertySymbol)?.name ?? interner.intern("")
        let propertyNameExprID = arena.appendExpr(
            .stringLiteral(propertyName),
            type: sema.types.stringType
        )
        body.append(.constValue(result: propertyNameExprID, value: .stringLiteral(propertyName)))
        let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
        let returnTypeSig = interner.intern(sema.types.renderType(propertyType))
        let returnTypeExprID = arena.appendExpr(
            .stringLiteral(returnTypeSig),
            type: sema.types.stringType
        )
        body.append(.constValue(result: returnTypeExprID, value: .stringLiteral(returnTypeSig)))
        let kPropertyExprID = arena.appendTemporary(type: sema.types.anyType)
        body.append(
            .call(
                symbol: nil,
                callee: interner.intern("__kk_kproperty_stub_create"),
                arguments: [propertyNameExprID, returnTypeExprID],
                result: kPropertyExprID,
                canThrow: false,
                thrownResult: nil
            )
        )
        return kPropertyExprID
    }

    /// Lower a property getter or setter body as a synthetic KIR function.
    ///
    /// Getter signature: `(<receiver>) -> PropertyType`
    /// Setter signature: `(<receiver>, value: PropertyType) -> Unit`
    func lowerAccessorBody(
        accessorBody: FunctionBody,
        propertySymbol: SymbolID,
        propertyType: TypeID,
        accessorKind: PropertyAccessorKind,
        setterParamName _: InternedString?,
        shared: KIRLoweringSharedContext,
        allDecls: inout [KIRDeclID]
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        // See the matching note in MemberLowerer.lowerSingleMemberFunction
        // (KSP-CAP-001): this can run nested inside an enclosing function's
        // lowering (a getter/setter body on an object literal property), so
        // the reset below must not discard that caller's scope.
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: propertySymbol)
        var params: [KIRParameter] = []

        // Add receiver parameter for extension properties or member properties.
        if let receiverType = extensionReceiverType {
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            )
        } else if let ownerSymbol,
                  let ownerSym = sema.symbols.symbol(ownerSymbol)
        {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            )
        }

        let returnType: TypeID
        let accessorName: InternedString
        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")
            // Keep `field` bound to its backing-field symbol so ExprLowerer can
            // resolve it through the active receiver's instance layout.
        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")
            let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            driver.ctx.setLocalValue(valueExprID, for: valueParamSymbol)
            // Sema binds the setter parameter name to a synthetic setter-value
            // symbol (offset -40_000) distinct from both the property symbol
            // and the backing field symbol.
            let semaSetterValueSymbol = SyntheticSymbolScheme.semaSetterValueSymbol(for: propertySymbol)
            driver.ctx.setLocalValue(valueExprID, for: semaSetterValueSymbol)
            // Keep `field` bound to its backing-field symbol so ExprLowerer can
            // resolve it through the active receiver's instance layout.
        }

        var body: KIRLoweringEmitContext = [.beginBlock]
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }

        switch accessorBody {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            var terminatedByReturn = false
            for exprID in exprIDs {
                if let expr = ast.arena.expr(exprID),
                   case let .returnExpr(value, _, _) = expr
                {
                    if let value {
                        let lowered = driver.lowerExpr(
                            value,
                            shared: shared,
                            emit: &body
                        )
                        body.append(.returnValue(lowered))
                    } else {
                        body.append(.returnUnit)
                    }
                    terminatedByReturn = true
                    break
                }
                lastValue = driver.lowerExpr(
                    exprID,
                    shared: shared,
                    emit: &body
                )
            }
            if !terminatedByReturn {
                if accessorKind == .getter, let lastValue {
                    body.append(.returnValue(lastValue))
                } else {
                    body.append(.returnUnit)
                }
            }
        case let .expr(exprID, _):
            let value = driver.lowerExpr(
                exprID,
                shared: shared,
                emit: &body
            )
            if accessorKind == .getter {
                body.append(.returnValue(value))
            } else {
                body.append(.returnUnit)
            }
        case .unit:
            body.append(.returnUnit)
        }
        body.append(.endBlock)

        // Use a synthetic symbol derived from the property symbol for the accessor.
        // Offsets are centralized in SyntheticSymbolScheme.
        let syntheticAccessorSymbol: SymbolID = switch accessorKind {
        case .getter:
            sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        case .setter:
            sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        }

        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: syntheticAccessorSymbol,
                    name: accessorName,
                    params: params,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.clearImplicitReceiver()
    }

    // MARK: - BUG-141: interface property getter dispatch

    /// Emits a getter accessor function (`(receiver) -> PropertyType`) that
    /// reads a stored property from its instance field. Concrete classes and
    /// object literals need one for every property that overrides an interface
    /// property so its getter can be registered into the interface's itable and
    /// dispatched through an interface-typed receiver.
    func synthesizeStoredPropertyGetterAccessor(
        propertySymbol: SymbolID,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        guard let ownerSym = sema.symbols.symbol(ownerSymbol) else { return }
        let fieldKey = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        guard let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[fieldKey] else {
            return
        }
        let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType

        let ownerType = sema.types.make(
            .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
        let params = [KIRParameter(symbol: receiverSymbol, type: ownerType)]
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
        let result = arena.appendTemporary(type: propType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [receiverExpr, offsetExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(result))
        body.append(.endBlock)

        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: getterSymbol,
                    name: interner.intern("get"),
                    params: params,
                    returnType: propType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
    }

    /// BUG-223: emits a setter accessor function (`(receiver, value) -> Unit`)
    /// that writes a stored property to its instance field. The `var`
    /// counterpart of `synthesizeStoredPropertyGetterAccessor` above — every
    /// class whose stored property ever needs virtual dispatch (the
    /// open/abstract root of an override chain, or a link further down it)
    /// needs one so a write through a base-typed reference can dispatch to it
    /// the same way a read dispatches to the getter.
    func synthesizeStoredPropertySetterAccessor(
        propertySymbol: SymbolID,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        guard let ownerSym = sema.symbols.symbol(ownerSymbol) else { return }
        let fieldKey = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        guard let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[fieldKey] else {
            return
        }
        let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType

        let ownerType = sema.types.make(
            .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
        let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
        let params = [
            KIRParameter(symbol: receiverSymbol, type: ownerType),
            KIRParameter(symbol: valueParamSymbol, type: propType),
        ]
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSymbol), type: propType)

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
        body.append(.constValue(result: valueExpr, value: .symbolRef(valueParamSymbol)))
        let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
        body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverExpr, offsetExpr, valueExpr],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnUnit)
        body.append(.endBlock)

        let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: setterSymbol,
                    name: interner.intern("set"),
                    params: params,
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
    }

    /// Emits a getter accessor stub (`(receiver) -> PropertyType`) for an
    /// abstract interface property. The stub is never executed — interface
    /// property reads dispatch through the itable — but it gives the dispatch
    /// site a concrete internal function whose signature matches the registered
    /// implementing getters, exactly as abstract interface methods emit a
    /// unit-returning stub.
    func synthesizeInterfacePropertyGetterStub(
        propertySymbol: SymbolID,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        guard let ownerSym = sema.symbols.symbol(ownerSymbol) else { return }
        let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType

        let ownerType = sema.types.make(
            .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
        let params = [KIRParameter(symbol: receiverSymbol, type: ownerType)]

        var body: KIRLoweringEmitContext = [.beginBlock]
        let defaultExpr = arena.appendExpr(.null, type: propType)
        body.append(.constValue(result: defaultExpr, value: .null))
        body.append(.returnValue(defaultExpr))
        body.append(.endBlock)

        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: getterSymbol,
                    name: interner.intern("get"),
                    params: params,
                    returnType: propType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
    }
}
