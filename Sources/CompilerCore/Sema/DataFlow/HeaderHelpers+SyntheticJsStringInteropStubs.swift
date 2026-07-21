/// Synthetic Kotlin/JS `JsString` interop surface.
///
/// Covers the `kotlin.js.JsString` external interface and the two conversion
/// extension functions that bridge between Kotlin `String` and the JS-native
/// string type:
///
///   - `String.toJsString(): JsString`
///   - `JsString.toString(): String`
///
/// These symbols are JS-target-only and must NOT be active during native/macOS
/// compilation. This file is intentionally excluded from the registration
/// dispatch (CLEANUP-STUB-056).
extension DataFlowSemaPhase {
    private func ensureJsStringInterface(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsString",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: jsAnySymbol)
        }

        symbols.setDirectSupertypes([jsAnySymbol], for: interfaceSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: interfaceSymbol)

        let interfaceType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(interfaceType, for: interfaceSymbol)

        return interfaceSymbol
    }

    private func registerStringToJsStringExtension(
        kotlinJsPkg: [InternedString],
        jsStringSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jsStringType = types.make(.classType(ClassType(
            classSymbol: jsStringSymbol,
            args: [],
            nullability: .nonNull
        )))

        let functionName = interner.intern("toJsString")
        let functionFQName = kotlinJsPkg + [functionName]
        let alreadyRegistered = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == types.stringType
                && signature.parameterTypes.isEmpty
                && signature.returnType == jsStringType
        }
        guard !alreadyRegistered else { return }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.stringType,
                parameterTypes: [],
                returnType: jsStringType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }
}
