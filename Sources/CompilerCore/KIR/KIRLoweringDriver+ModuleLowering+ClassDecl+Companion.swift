
extension KIRLoweringDriver {
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

        let ast = shared.ast
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
        let companionReceiverExpr = arena.appendExpr(.symbolRef(companionSymbol), type: companionType)

        var body: KIRLoweringEmitContext = [.beginBlock]
        let needsDispatchObject = sema.symbols.nominalLayout(for: companionSymbol)?.vtableSize ?? 0 > 0
        let companionObjectValue: KIRExprID
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
            companionObjectValue = allocatedObject
        } else {
            body.append(.constValue(result: companionReceiverExpr, value: .symbolRef(companionSymbol)))
            companionObjectValue = companionReceiverExpr
        }
        ctx.setImplicitReceiver(symbol: companionSymbol, exprID: companionObjectValue)

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
        return declIDs
    }
}
