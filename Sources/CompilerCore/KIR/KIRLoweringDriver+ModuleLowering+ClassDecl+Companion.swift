
extension KIRLoweringDriver {
    /// BUG-274: Kotlin runs a companion object's body lazily, on first
    /// access, not eagerly at program start. This keeps the eager half --
    /// the companion's dispatch-object allocation (when it has virtual
    /// methods) and its type-edge/vtable registrations -- running
    /// unconditionally during module initialization (registered via
    /// `registerCompanionInitializer`, unchanged from before). The implicit
    /// super-constructor call, property initializers, and `init` blocks move
    /// into a separate function guarded by a `$initialized` flag
    /// (`synthesizeCompanionLazyInit` below), registered via
    /// `ctx.registerObjectLazyInit` instead so call sites that touch the
    /// companion's state trigger it on demand rather than at module start.
    func synthesizeCompanionInitializerIfNeeded(
        companionDeclID: DeclID?,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        guard let companionDeclID,
              let decl = shared.ast.arena.decl(companionDeclID),
              case let .objectDecl(companionDecl) = decl,
              let companionSymbol = shared.sema.bindings.declSymbols[companionDeclID]
        else {
            return []
        }

        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__companion_init_\(ownerSymbol.rawValue)_\(companionSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))

        var body: KIRLoweringEmitContext = [.beginBlock]
        let needsDispatchObject = sema.symbols.nominalLayout(for: companionSymbol)?.vtableSize ?? 0 > 0
        if needsDispatchObject {
            let layout = sema.symbols.nominalLayout(for: companionSymbol)
            let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
            let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: sema.types.intType)
            body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))

            let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: companionSymbol,
                sema: sema,
                interner: interner
            )
            let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
            body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))

            let allocatedObject = arena.appendTemporary(type: companionType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: allocatedObject,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.storeGlobal(value: allocatedObject, symbol: companionSymbol))

            for superSymbol in sema.symbols.directSupertypes(for: companionSymbol) {
                let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: superSymbol,
                    sema: sema,
                    interner: interner
                )
                let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: sema.types.intType)
                body.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
                let registerResult = arena.appendTemporary(type: sema.types.intType)
                let superKind = sema.symbols.symbol(superSymbol)?.kind
                let registerCallee: InternedString = if superKind == .interface {
                    interner.intern("kk_type_register_iface")
                } else {
                    interner.intern("kk_type_register_super")
                }
                body.append(.call(
                    symbol: nil,
                    callee: registerCallee,
                    arguments: [classIDExpr, parentExpr],
                    result: registerResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            appendObjectVtableMethodRegistrations(
                objectValue: allocatedObject,
                nominalSymbol: companionSymbol,
                driver: self,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
        }

        body.append(.returnUnit)
        body.append(.endBlock)

        let initDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: initializerSymbol,
                    name: initializerName,
                    params: [],
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false,
                    sourceRange: companionDecl.range
                )
            )
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)

        var declIDs: [KIRDeclID] = [initDeclID]
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()

        declIDs.append(contentsOf: synthesizeCompanionLazyInit(
            companionDecl,
            companionSymbol: companionSymbol,
            companionType: companionType,
            needsDispatchObject: needsDispatchObject,
            shared: shared
        ))
        return declIDs
    }

    /// BUG-274: the lazy half of `synthesizeCompanionInitializerIfNeeded` --
    /// the implicit super-constructor call, property initializers, and
    /// `init` blocks in declaration order -- guarded by a `$initialized`
    /// flag so it runs at most once, on whichever access to the companion's
    /// state comes first. When the companion has a dispatch object, its
    /// handle already exists (allocated eagerly by
    /// `synthesizeCompanionInitializerIfNeeded`), so this function only
    /// needs to `loadGlobal` it; otherwise it re-derives the same bare
    /// `symbolRef` value the eager function used transiently for its own
    /// (now-removed) super-constructor-call argument.
    private func synthesizeCompanionLazyInit(
        _ companionDecl: ObjectDecl,
        companionSymbol: SymbolID,
        companionType: TypeID,
        needsDispatchObject: Bool,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        let (flagSymbol, flagGlobalDeclID) = makeObjectLazyInitFlag(
            for: companionSymbol, declSite: companionDecl.range, shared: shared
        )

        let ensureInitSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let ensureInitName = interner.intern("__companion_lazy_init_\(companionSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        var body: KIRLoweringEmitContext = [.beginBlock]
        let companionObjectValue: KIRExprID
        if needsDispatchObject {
            let handleExpr = arena.appendExpr(.symbolRef(companionSymbol), type: companionType)
            body.append(.loadGlobal(result: handleExpr, symbol: companionSymbol))
            companionObjectValue = handleExpr
        } else {
            let receiverExpr = arena.appendExpr(.symbolRef(companionSymbol), type: companionType)
            body.append(.constValue(result: receiverExpr, value: .symbolRef(companionSymbol)))
            companionObjectValue = receiverExpr
        }
        ctx.setImplicitReceiver(symbol: companionSymbol, exprID: companionObjectValue)

        let boolType = sema.types.booleanType
        let trueExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
        body.append(.constValue(result: trueExpr, value: .boolLiteral(true)))
        let flagLoadExpr = arena.appendExpr(.symbolRef(flagSymbol), type: boolType)
        body.append(.loadGlobal(result: flagLoadExpr, symbol: flagSymbol))
        let alreadyInitializedLabel = ctx.makeLoopLabel()
        body.append(.jumpIfEqual(lhs: flagLoadExpr, rhs: trueExpr, target: alreadyInitializedLabel))
        body.append(.storeGlobal(value: trueExpr, symbol: flagSymbol))

        emitNamedObjectSuperConstructorCall(
            companionDecl,
            objectSymbol: companionSymbol,
            objectValue: companionObjectValue,
            shared: shared,
            body: &body
        )

        // Emit property initializers and init blocks in declaration order.
        for member in companionDecl.classBodyInitOrder {
            switch member {
            case let .property(index):
                guard index < companionDecl.memberProperties.count else { continue }
                let propertyDeclID = companionDecl.memberProperties[index]
                guard let propertyDecl = ast.arena.decl(propertyDeclID),
                      case let .propertyDecl(property) = propertyDecl,
                      let propertySymbol = sema.bindings.declSymbols[propertyDeclID]
                else {
                    continue
                }
                if property.delegateExpression != nil {
                    continue
                }
                guard let initializer = property.initializer else {
                    continue
                }
                let initializerValue = lowerExpr(
                    initializer,
                    shared: shared,
                    emit: &body
                )
                let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
                let propertyType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
                let targetRef = arena.appendExpr(.symbolRef(targetSymbol), type: propertyType)
                body.append(.constValue(result: targetRef, value: .symbolRef(targetSymbol)))
                body.append(.copy(from: initializerValue, to: targetRef))
            case let .initBlock(index):
                guard index < companionDecl.initBlocks.count else { continue }
                let initBlock = companionDecl.initBlocks[index]
                switch initBlock {
                case let .block(exprIDs, _):
                    for exprID in exprIDs {
                        _ = lowerExpr(
                            exprID,
                            shared: shared,
                            emit: &body
                        )
                    }
                case let .expr(exprID, _):
                    _ = lowerExpr(
                        exprID,
                        shared: shared,
                        emit: &body
                    )
                case .unit:
                    break
                }
            }
        }

        body.append(.label(alreadyInitializedLabel))
        body.append(.returnUnit)
        body.append(.endBlock)

        let ensureInitDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: ensureInitSymbol,
                    name: ensureInitName,
                    params: [],
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false,
                    sourceRange: companionDecl.range
                )
            )
        )
        ctx.registerObjectLazyInit(
            for: companionSymbol,
            ensureInitSymbol: ensureInitSymbol,
            ensureInitName: ensureInitName,
            flagSymbol: flagSymbol
        )

        var declIDs: [KIRDeclID] = [flagGlobalDeclID, ensureInitDeclID]
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()
        return declIDs
    }
}
