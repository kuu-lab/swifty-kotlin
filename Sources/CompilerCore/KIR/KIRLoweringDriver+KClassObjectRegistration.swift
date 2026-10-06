extension KIRLoweringDriver {
    /// Registers the existing singleton and its guarded initializer for erased KClass queries.
    func appendKClassObjectRegistration(
        objectSymbol: SymbolID,
        objectType: TypeID,
        ensureInitSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        instructions: inout [KIRInstruction]
    ) {
        let arena = shared.arena
        let sema = shared.sema
        let interner = shared.interner
        let token = RuntimeTypeCheckToken.encode(type: objectType, sema: sema, interner: interner)
        let tokenExpr = arena.appendExpr(.intLiteral(token), type: sema.types.intType)
        let objectExpr = arena.appendTemporary(type: objectType)
        let initializerExpr = arena.appendExpr(.symbolRef(ensureInitSymbol), type: sema.types.intType)
        instructions.append(contentsOf: [
            .constValue(result: tokenExpr, value: .intLiteral(token)),
            .loadGlobal(result: objectExpr, symbol: objectSymbol),
            .constValue(result: initializerExpr, value: .symbolRef(ensureInitSymbol)),
            .call(symbol: nil, callee: interner.intern("__kk_kclass_register_object"),
                  arguments: [tokenExpr, objectExpr, initializerExpr],
                  result: arena.appendTemporary(type: sema.types.intType), canThrow: false, thrownResult: nil),
        ])
    }
}
