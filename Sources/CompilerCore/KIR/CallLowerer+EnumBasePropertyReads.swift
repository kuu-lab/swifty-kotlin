extension CallLowerer {
    /// Abstract Enum receivers carry tagged boxes, without a stored-field layout
    /// or a statically known per-enum name helper. Match the bound property so
    /// unrelated properties and extension properties named `name` stay untouched.
    func tryLowerEnumBasePropertyRead(
        propertySymbol: SymbolID?,
        receiver: KIRExprID,
        receiverType: TypeID?,
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let propertySymbol,
              let property = sema.symbols.symbol(propertySymbol),
              property.kind == .property,
              property.fqName == ["kotlin", "Enum", "name"].map(interner.intern)
                || property.fqName == ["kotlin", "Enum", "ordinal"].map(interner.intern)
        else { return nil }
        if let receiverType,
           let (_, receiverClass) = resolveClassTypeSymbol(receiverType, sema: sema),
           receiverClass.kind == .enumClass
        {
            return nil
        }
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            callee: interner.intern(property.name == interner.intern("name")
                ? "__kk_enum_name" : "kk_unbox_int"),
            arguments: [receiver],
            result: result,
            canThrow: false
        ))
        return result
    }
}
