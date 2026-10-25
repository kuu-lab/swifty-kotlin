extension CallLowerer {
    /// Enum values are raw ordinals when their static type is concrete. Pass
    /// the nominal enum ID alongside the ordinal so the runtime can use the
    /// same identity hash as an enum box after Any erasure.
    func tryEmitEnumHashCodeCall(
        chosenCallee: SymbolID?,
        receiver: MemberCallReceiver,
        arguments: [KIRExprID],
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        guard let chosenCallee,
              sema.symbols.symbol(chosenCallee)?.fqName == ["kotlin", "Enum", "hashCode"].map(interner.intern),
              sema.symbols.externalLinkName(for: chosenCallee) == "kk_any_member_hashCode",
              arguments.first == receiver.loweredID,
              let receiverType = receiver.type(in: sema),
              let (receiverClassType, receiverClassSymbol) = resolveClassTypeSymbol(
                  sema.types.makeNonNullable(receiverType), sema: sema
              ),
              receiverClassType.nullability == .nonNull,
              receiverClassSymbol.kind == .enumClass
        else {
            return false
        }

        let classID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: receiverClassType.classSymbol,
            symbols: sema.symbols,
            interner: interner
        )
        guard classID != 0 else { return false }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let ordinal = arena.appendTemporary(type: intType)
        instructions.append(.call(callee: interner.intern("kk_unbox_int"), arguments: [receiver.loweredID], result: ordinal, canThrow: false))

        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
        instructions.append(.call(callee: interner.intern("kk_enum_hash_code"), arguments: [ordinal, classIDExpr], result: result, canThrow: false))
        return true
    }
}
