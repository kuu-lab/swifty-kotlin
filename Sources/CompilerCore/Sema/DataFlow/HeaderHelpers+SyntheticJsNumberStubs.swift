
/// Synthetic Kotlin/JS `JsNumber` external abstract class surface.
///
/// Registers `kotlin.js.JsNumber` as an abstract class with supertype `JsAny`
/// and member conversion functions `toDouble()` and `toInt()`.
extension DataFlowSemaPhase {
    func registerSyntheticJsNumberStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)

        let className = interner.intern("JsNumber")
        let classFQName = kotlinJsPkg + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName),
           symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: classSymbol)
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsAnySymbol)
        }
        symbols.setDirectSupertypes([jsAnySymbol], for: classSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: classSymbol)

        registerJsNumberMemberFunction(
            named: "toDouble",
            externalLinkName: "kk_js_number_toDouble",
            returnType: types.doubleType,
            ownerSymbol: classSymbol,
            ownerType: classType,
            symbols: symbols,
            interner: interner
        )
        registerJsNumberMemberFunction(
            named: "toInt",
            externalLinkName: "kk_js_number_toInt",
            returnType: types.intType,
            ownerSymbol: classSymbol,
            ownerType: classType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsNumberMemberFunction(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty && sig.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: memberSymbol
        )
    }
}
