extension CallLowerer {
    /// Keep the JVM's constructor ordering when argument lowering later inlines a function call.
    func shouldDeferCompanionInitializationUntilArgumentsAreEvaluated(
        exprID: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let callBinding = sema.bindings.callBinding(for: exprID),
              let constructor = sema.symbols.symbol(callBinding.chosenCallee),
              constructor.kind == .constructor,
              let ownerSymbol = sema.symbols.parentSymbol(for: callBinding.chosenCallee),
              sema.symbols.companionObjectSymbol(for: ownerSymbol) != nil
                || sema.symbols.companionBlockObjectSymbol(for: ownerSymbol, interner: interner) != nil
        else {
            return false
        }

        return args.contains { argument in
            guard let argumentBinding = sema.bindings.callBinding(for: argument.expr),
                  let argumentFunction = sema.symbols.symbol(argumentBinding.chosenCallee)
            else {
                return false
            }
            return argumentFunction.flags.contains(.inlineFunction)
        }
    }

    func emitCompanionInitializationForConstructorCall(
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
                ?? sema.symbols.companionBlockObjectSymbol(for: ownerSymbol, interner: interner)
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
