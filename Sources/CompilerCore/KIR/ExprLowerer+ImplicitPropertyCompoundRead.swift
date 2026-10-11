extension ExprLowerer {
    /// Reads a bare member before its compound assignment invokes a setter.
    /// A custom setter does not require a custom getter: stored reads keep
    /// using the backing-field slot, while delegated/custom reads use get.
    func lowerImplicitPropertyCompoundRead(
        propertySymbol: SymbolID,
        receiver: KIRExprID,
        callExprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (value: KIRExprID, receiver: KIRExprID)? {
        guard let owner = sema.symbols.parentSymbol(for: propertySymbol) else { return nil }
        let usesGetter = driver.callLowerer.memberPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema)
        let offset = sema.symbols.nominalLayout(for: owner)?.fieldOffsets[
            sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        ]
        guard usesGetter || offset != nil else { return nil }
        let receiver = resolveOuterChainValue(
            from: receiver, to: owner, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        ) ?? receiver
        let type = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
        let value = arena.appendTemporary(type: type)
        if usesGetter {
            let getter = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
            let arguments = driver.callLowerer.propertyAccessorArguments(
                for: getter, arguments: [receiver], callExprID: callExprID,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            instructions.append(.call(
                symbol: getter, callee: interner.intern("get"), arguments: arguments,
                result: value, canThrow: false, thrownResult: nil
            ))
        } else {
            guard let offset else { return nil }
            let slot = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
            instructions.append(.constValue(result: slot, value: .intLiteral(Int64(offset))))
            instructions.append(.call(
                symbol: nil, callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiver, slot], result: value, canThrow: false, thrownResult: nil
            ))
        }
        return (value, receiver)
    }
}
