
/// Lowering for `lateinit` property initialization checks.
extension CallLowerer {
    func tryLowerLateinitIsInitialized(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty,
              calleeName == KnownCompilerNames(interner: interner).isInitialized,
              case let .callableRef(boundReceiver, _, _) = ast.arena.expr(receiverExpr),
              // An unbound `C::p` reference's "receiver" is the class name, not
              // an instance — SEMA rejects it, but never lower it as one here.
              !sema.bindings.isUnboundCallableRef(receiverExpr),
              let propertySymbol = sema.bindings.identifierSymbol(for: receiverExpr),
              let propertyInfo = sema.symbols.symbol(propertySymbol),
              propertyInfo.kind == .property,
              propertyInfo.flags.contains(.lateinitProperty)
        else {
            return nil
        }

        let storageExpr: KIRExprID
        if let parentSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let parentInfo = sema.symbols.symbol(parentSymbol),
           parentInfo.kind != .package,
           parentInfo.kind != .object
        {
            // `c::name` carries its receiver explicitly; a bare `::name`
            // inside the declaring class reads the implicit `this`.
            let instanceExpr: KIRExprID
            if let boundReceiver {
                instanceExpr = driver.lowerExpr(
                    boundReceiver,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                guard let implicitReceiver = driver.ctx.activeImplicitReceiverExprID() else {
                    return nil
                }
                instanceExpr = implicitReceiver
            }
            guard let fieldOffset = sema.symbols.nominalLayout(for: parentSymbol)?.fieldOffsets[
                sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            ]
            else {
                return nil
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let loaded = arena.appendTemporary(type: propertyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [instanceExpr, offsetExpr],
                result: loaded,
                canThrow: false,
                thrownResult: nil
            ))
            storageExpr = loaded
        } else {
            let storageSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            let storageType = sema.symbols.propertyType(for: storageSymbol)
                ?? sema.symbols.propertyType(for: propertySymbol)
                ?? sema.types.anyType
            let loaded = arena.appendExpr(.symbolRef(storageSymbol), type: storageType)
            instructions.append(.loadGlobal(result: loaded, symbol: storageSymbol))
            storageExpr = loaded
        }

        let resultType = sema.bindings.exprType(for: exprID)
            ?? sema.types.make(.primitive(.boolean, .nonNull))
        let result = arena.appendTemporary(type: resultType)
        emitNonThrowingCall(
            callee: interner.intern("kk_lateinit_is_initialized"),
            arg: storageExpr,
            result: result,
            into: &instructions
        )
        return result
    }

}
