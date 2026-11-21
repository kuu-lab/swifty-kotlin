extension DataFlowSemaPhase {
    /// ships as `@InlineOnly` (so they carry no bytecode for the JVM classpath
    /// index to import). Without them, `String.format(...)` has no companion
    /// candidate and overload resolution falls back to the `String.format`
    /// extension, coercing the `StringCompanionObject` receiver to `String`
    /// and emitting a `checkcast` that fails at runtime. The JVM backend
    func registerStringCompanionFormatMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        stringClassSymbol: SymbolID
    ) {
        guard let companionSymbol = symbols.companionObjectSymbol(for: stringClassSymbol),
              let companionInfo = symbols.symbol(companionSymbol)
        else { return }

        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))

        // For a `vararg` parameter, `parameterTypes` stores the element type
        // (`Any?`); the array form is derived by callers when packing.
        registerStringCompanionFormatMember(
            companionSymbol: companionSymbol,
            companionFQName: companionInfo.fqName,
            parameterTypes: [types.stringType, types.nullableAnyType],
            valueParameterIsVararg: [false, true],
            companionType: companionType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerStringCompanionFormatMember(
        companionSymbol: SymbolID,
        companionFQName: [InternedString],
        parameterTypes: [TypeID],
        valueParameterIsVararg: [Bool],
        companionType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let memberName = interner.intern("format")
        let memberFQName = companionFQName + [memberName]
        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes == parameterTypes && signature.returnType == types.stringType
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(companionSymbol, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: companionType,
                parameterTypes: parameterTypes,
                returnType: types.stringType,
                valueParameterIsVararg: valueParameterIsVararg
            ),
            for: memberSymbol
        )
    }
}
