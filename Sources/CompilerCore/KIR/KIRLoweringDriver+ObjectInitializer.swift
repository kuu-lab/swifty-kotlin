
extension KIRLoweringDriver {
    /// Synthesise an initializer function for a top-level `object` declaration.
    ///
    /// The generated function emits property initializers and init blocks in
    /// declaration order using `classBodyInitOrder`, matching Kotlin's
    /// guaranteed top-to-bottom initialization semantics.  The function is
    /// registered via `registerCompanionInitializer` so that it is called once
    /// during module initialization (injected into `main`).
    ///
    /// Every source-backed top-level object gets a heap object via
    /// `kk_object_new` and stores it in the object's global slot. Objects that
    /// participate in runtime dispatch additionally register their
    /// vtable/itable methods.
    func synthesizeObjectInitializer(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema

        // A source-backed top-level singleton must have a real runtime handle
        // even when it has no interfaces or virtual slots: it may cross an Any
        // boundary.
        let interfaceSupertypes = ctx.nominalDispatchCache.transitiveInterfaceSupertypes(
            of: objectSymbol,
            sema: sema
        )

        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__object_init_\(objectSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol, args: [], nullability: .nonNull
        )))
        let objectReceiverExpr = arena.appendExpr(.symbolRef(objectSymbol), type: objectType)
        ctx.setImplicitReceiver(symbol: objectSymbol, exprID: objectReceiverExpr)

        var body: KIRLoweringEmitContext = [.beginBlock]

        // Allocate the singleton handle and store it in the global slot so
        // generic Any rendering and virtual dispatch can recognize the object.
        let intType = sema.types.intType
        let layout = sema.symbols.nominalLayout(for: objectSymbol)
        let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol, sema: sema, interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocatedObj = arena.appendTemporary(type: objectType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocatedObj,
            canThrow: false,
            thrownResult: nil
        ))

        // Store the allocated object pointer in the global slot.
        body.append(.storeGlobal(value: allocatedObj, symbol: objectSymbol))

        var typeEdgeInstructions: [KIRInstruction] = []
        appendNominalSupertypeEdgeRegistrations(
            childSymbol: objectSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &typeEdgeInstructions
        )
        body.append(contentsOf: typeEdgeInstructions)

        // Register itable methods for each interface.
        if let objectLayout = sema.symbols.nominalLayout(for: objectSymbol) {
            for interfaceSymbol in interfaceSupertypes {
                guard let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else { continue }
                let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
                let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: interfaceSymbol,
                    sema: sema,
                    interner: interner
                )
                let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
                body.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
                let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
                body.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
                let registerIfaceResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_object_register_itable_iface"),
                    arguments: [allocatedObj, interfaceTypeExpr, ifaceSlotExpr],
                    result: registerIfaceResult,
                    canThrow: false,
                    thrownResult: nil
                ))

                // Walk the interface methods to find each method that needs registration.
                for (methodSymbol, methodSlotInt) in kirItableMethodEntries(
                    for: interfaceSymbol,
                    interfaceLayout: interfaceLayout,
                    sema: sema,
                    interner: interner
                ) {
                    let methodSlot = Int64(methodSlotInt)
                    // Find the override in the object's member functions.
                    let implementationSymbol = ctx.nominalDispatchCache.itableImplementation(
                        for: methodSymbol,
                        in: objectSymbol,
                        sema: sema,
                        interner: interner
                    )
                    let bridgeSymbol = itableBridgeSymbolForMethod(
                        interfaceMethod: methodSymbol,
                        implementation: implementationSymbol,
                        nominalSymbol: objectSymbol,
                        driver: self,
                        arena: arena,
                        sema: sema,
                        interner: interner
                    )
                    let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
                    body.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
                    let methodFnExpr = arena.appendExpr(.symbolRef(bridgeSymbol), type: intType)
                    body.append(.constValue(result: methodFnExpr, value: .symbolRef(bridgeSymbol)))
                    let registerMethodResult = arena.appendTemporary(type: intType)
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_object_register_itable_method"),
                        arguments: [allocatedObj, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                        result: registerMethodResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
            }
            // BUG-141: register interface property getters into the itable.
            appendObjectItablePropertyGetterRegistrations(
                objectValue: allocatedObj,
                nominalSymbol: objectSymbol,
                sema: sema,
                cache: ctx.nominalDispatchCache,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
        }
        appendObjectVtableMethodRegistrations(
            objectValue: allocatedObj,
            nominalSymbol: objectSymbol,
            driver: self,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )
        appendObjectAnyToStringRegistration(
            objectValue: allocatedObj,
            nominalSymbol: objectSymbol,
            driver: self,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )

        // Companions are excluded: `synthesizeCompanionInitializerIfNeeded`
        // already emits their super delegation, and an interface companion can
        // still reach this initializer through the nested-object path.
        if !objectDecl.modifiers.contains(.companion) {
            emitNamedObjectSuperConstructorCall(
                objectDecl,
                objectSymbol: objectSymbol,
                objectValue: allocatedObj,
                shared: shared,
                body: &body
            )
        }

        emitObjectBodyInitializers(objectDecl, shared: shared, body: &body)

        body.append(.returnUnit)
        body.append(.endBlock)

        let initDeclID = arena.appendDecl(
            .function(KIRFunction(
                symbol: initializerSymbol, name: initializerName,
                params: [], returnType: sema.types.unitType,
                body: body, isSuspend: false, isInline: false,
                sourceRange: objectDecl.range
            ))
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)

        var declIDs: [KIRDeclID] = [initDeclID]
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()
        return declIDs
    }

    /// Emits the implicit `super(...)` call of a named object declaration's
    /// superclass, e.g. `object Named : Base(x)` (BUG-264). Kotlin runs the
    /// superclass constructor before the object's own initializers, so the
    /// superclass's property initializers and `init` blocks — which write
    /// into the same instance at the layout offsets the object inherits —
    /// must execute here. Without this call the object keeps the zeroed
    /// defaults for every inherited property (same root cause as BUG-155 for
    /// named classes and KSP-CAP-018 for object literals).
    func emitNamedObjectSuperConstructorCall(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        objectValue: KIRExprID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        guard let superclassSymbol = sema.symbols.directSupertypes(for: objectSymbol).first(where: {
            let kind = sema.symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }),
        let superclassInfo = sema.symbols.symbol(superclassSymbol)
        else {
            return
        }
        let candidates = sema.symbols.lookupAll(
            fqName: superclassInfo.fqName + [interner.intern("<init>")]
        )
        guard let superCtorSymbol = resolveObjectSuperConstructor(
            candidates: candidates,
            argExprs: objectDecl.superTypeConstructorArgs.map(\.expr),
            sema: sema
        ),
        sema.symbols.externalLinkName(for: superCtorSymbol)?.isEmpty ?? true
        else {
            return
        }
        if sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) == true,
           sema.symbols.parentSymbol(for: superCtorSymbol) == sema.types.anyClassSymbol
        {
            // Any's compiler-provided constructor has no body to delegate to.
            return
        }

        var argIDs: [KIRExprID] = [objectValue]
        for arg in objectDecl.superTypeConstructorArgs {
            argIDs.append(lowerExpr(arg.expr, shared: shared, emit: &body))
        }

        let resultID = arena.appendTemporary(type: sema.types.unitType)
        body.append(.call(
            symbol: superCtorSymbol,
            callee: interner.intern("<init>"),
            arguments: argIDs,
            result: resultID,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        ))
    }

    /// Picks which of the superclass's `<init>` overloads `argExprs` (the
    /// `object ... : Base(args)` header) actually calls. A single candidate
    /// is used as-is; multiple candidates are first narrowed by arity, then —
    /// if more than one still matches — by parameter type (using each
    /// argument's Sema-resolved expression type, with a type-parameter
    /// position treated as a wildcard, mirroring `resolveOverriddenVtableSlot`
    /// in `VtableOverrideMatching.swift`). Falls back to the first candidate
    /// when nothing narrows cleanly (e.g. a defaulted trailing parameter
    /// omitted at the call site) rather than emitting no super call at all —
    /// the same residual gap `emitSuperConstructorDelegation` has for named
    /// classes, since neither path expands omitted default arguments.
    func resolveObjectSuperConstructor(
        candidates: [SymbolID],
        argExprs: [ExprID],
        sema: SemaModule
    ) -> SymbolID? {
        guard candidates.count > 1 else {
            return candidates.first
        }
        let arityMatches = candidates.filter {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == argExprs.count
        }
        guard arityMatches.count > 1 else {
            return arityMatches.first ?? candidates.first
        }
        let argTypes = argExprs.map { sema.bindings.exprTypes[$0] }
        let typeMatches = arityMatches.filter { candidate in
            guard let parameterTypes = sema.symbols.functionSignature(for: candidate)?.parameterTypes else {
                return false
            }
            for (paramType, argType) in zip(parameterTypes, argTypes) {
                guard let argType else { continue }
                if case .typeParam = sema.types.kind(of: paramType) { continue }
                if paramType != argType { return false }
            }
            return true
        }
        return typeMatches.count == 1 ? typeMatches[0] : arityMatches[0]
    }

    private func emitObjectBodyInitializers(
        _ objectDecl: ObjectDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena

        for member in objectDecl.classBodyInitOrder {
            switch member {
            case let .property(index):
                guard index < objectDecl.memberProperties.count else { continue }
                let propertyDeclID = objectDecl.memberProperties[index]
                guard let propertyDecl = ast.arena.decl(propertyDeclID),
                      case let .propertyDecl(property) = propertyDecl,
                      let propertySymbol = sema.bindings.declSymbols[propertyDeclID]
                else { continue }
                if property.delegateExpression != nil { continue }
                guard let initializer = property.initializer else { continue }
                let initializerValue = lowerExpr(initializer, shared: shared, emit: &body)
                let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
                let propertyType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
                let targetRef = arena.appendExpr(.symbolRef(targetSymbol), type: propertyType)
                body.append(.constValue(result: targetRef, value: .symbolRef(targetSymbol)))
                body.append(.copy(from: initializerValue, to: targetRef))
            case let .initBlock(index):
                guard index < objectDecl.initBlocks.count else { continue }
                let initBlock = objectDecl.initBlocks[index]
                switch initBlock {
                case let .block(exprIDs, _):
                    for exprID in exprIDs {
                        _ = lowerExpr(exprID, shared: shared, emit: &body)
                    }
                case let .expr(exprID, _):
                    _ = lowerExpr(exprID, shared: shared, emit: &body)
                case .unit:
                    break
                }
            }
        }
    }
}
