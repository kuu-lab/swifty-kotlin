import Foundation

/// Synthetic stdlib stubs for `buildList`.
/// buildList<E>(builderAction: MutableList<E>.() -> Unit): List<E>
/// buildList<E>(capacity: Int, builderAction: MutableList<E>.() -> Unit): List<E>
/// Lowering rewrites these to `kk_build_list` / `kk_build_list_with_capacity`.
extension DataFlowSemaPhase {
    func registerSyntheticBuildListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) {
        let buildListName = interner.intern("buildList")
        let buildListFQName = kotlinCollectionsPkg + [buildListName]
        let eName = interner.intern("E")
        registerSyntheticBuildListOverload(
            named: buildListName,
            fqName: buildListFQName,
            packageFQName: kotlinCollectionsPkg,
            typeParameterName: eName,
            extraParameterTypes: [],
            extraParameterNames: [],
            externalLinkName: nil,
            listSymbol: listSymbol,
            mutableListSymbol: mutableListSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticBuildListOverload(
            named: buildListName,
            fqName: buildListFQName,
            packageFQName: kotlinCollectionsPkg,
            typeParameterName: eName,
            extraParameterTypes: [types.intType],
            extraParameterNames: ["capacity"],
            externalLinkName: "kk_build_list_with_capacity",
            listSymbol: listSymbol,
            mutableListSymbol: mutableListSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticBuildListOverload(
        named buildListName: InternedString,
        fqName buildListFQName: [InternedString],
        packageFQName: [InternedString],
        typeParameterName: InternedString,
        extraParameterTypes: [TypeID],
        extraParameterNames: [String],
        externalLinkName: String?,
        listSymbol: SymbolID,
        mutableListSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard extraParameterTypes.count == extraParameterNames.count else {
            return
        }
        let parameterCount = extraParameterTypes.count + 1
        let alreadyDefined = symbols.lookupAll(fqName: buildListFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == parameterCount
                && signature.typeParameterSymbols.count == 1
        }
        if alreadyDefined {
            return
        }

        let eFQName = buildListFQName + [typeParameterName]
        let eSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParameterName,
            fqName: eFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let eType = types.make(.typeParam(TypeParamType(symbol: eSymbol, nullability: .nonNull)))
        let mutableListOfEType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(eType)],
            nullability: .nonNull
        )))
        let listOfEType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(eType)],
            nullability: .nonNull
        )))
        let builderActionType = types.make(.functionType(FunctionType(
            receiver: mutableListOfEType,
            params: [],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let buildListSymbol = symbols.define(
            kind: .function,
            name: buildListName,
            fqName: buildListFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: buildListSymbol)
        }
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: buildListSymbol)
        }
        symbols.setParentSymbol(buildListSymbol, for: eSymbol)

        let parameterNames = extraParameterNames + ["builderAction"]
        var valueParameterSymbols: [SymbolID] = []
        valueParameterSymbols.reserveCapacity(parameterNames.count)
        for parameterName in parameterNames {
            let parameterNameID = interner.intern(parameterName)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterNameID,
                fqName: buildListFQName + [parameterNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(buildListSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: extraParameterTypes + [builderActionType],
                returnType: listOfEType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: [eSymbol],
                classTypeParameterCount: 0
            ),
            for: buildListSymbol
        )
    }
}
