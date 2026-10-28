extension DeclTypeChecker {
    func addingCompanionLookupReceiver(
        to context: TypeInferenceContext,
        receiverType: TypeID,
        enabled: Bool
    ) -> TypeInferenceContext {
        guard enabled,
              let owner = driver.helpers.nominalSymbol(
                of: context.sema.types.makeNonNullable(receiverType),
                types: context.sema.types
              )
        else {
            return context
        }

        let symbols = context.sema.symbols
        let receiver = symbols.companionBlockObjectSymbol(for: owner, interner: context.interner)
            ?? symbols.companionObjectSymbol(for: symbols.actualSymbol(for: owner) ?? owner)
            ?? symbols.companionObjectSymbol(for: owner)
        guard let receiver else { return context }
        let companionType = context.sema.types.make(.classType(ClassType(
            classSymbol: receiver,
            args: [],
            nullability: .nonNull
        )))
        let label = symbols.symbol(receiver)?.name ?? context.interner.intern("Companion")
        return context.withOuterReceiver(label: label, type: companionType, symbol: receiver)
    }
}
