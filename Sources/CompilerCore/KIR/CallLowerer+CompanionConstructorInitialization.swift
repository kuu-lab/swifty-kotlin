extension CallLowerer {
    func emitCompanionInitializationBeforeConstructorArguments(
        exprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let callBinding = sema.bindings.callBinding(for: exprID),
              let constructor = sema.symbols.symbol(callBinding.chosenCallee),
              constructor.kind == .constructor,
              let ownerSymbol = sema.symbols.parentSymbol(for: callBinding.chosenCallee),
              let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerSymbol)
        else {
            return
        }

        driver.emitObjectLazyInitGuardIfNeeded(
            objectSymbol: companionSymbol,
            arena: arena,
            sema: sema,
            interner: interner,
            instructions: &instructions
        )
    }
}
