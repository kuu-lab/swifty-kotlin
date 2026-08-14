
/// Synthetic stdlib top-level functions for kotlin.math (STDLIB-052).
/// These stubs are intentionally minimal and only cover the math entry points
/// currently needed by the compiler front-end and runtime.
extension DataFlowSemaPhase {
    func registerSyntheticMathStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinMathPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("math")],
            symbols: symbols
        )

        // STDLIB-500~509: Float overloads for trig/math functions
        let floatType = types.floatType

        // STDLIB-510~511: roundToInt / roundToLong extension functions
        registerSyntheticMathTopLevelFunction(
            named: "roundToInt",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: types.intType,
            externalLinkName: "kk_float_roundToInt",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "roundToInt",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.intType,
            externalLinkName: "kk_double_roundToInt",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "roundToLong",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: types.longType,
            externalLinkName: "kk_float_roundToLong",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "roundToLong",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.longType,
            externalLinkName: "kk_double_roundToLong",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-512~513: ulp / nextUp / nextDown extension properties
        registerSyntheticMathTopLevelFunction(
            named: "ulp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_double_ulp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextUp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_double_nextUp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextDown",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_double_nextDown",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "ulp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: floatType,
            externalLinkName: "kk_float_ulp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextUp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: floatType,
            externalLinkName: "kk_float_nextUp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextDown",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: floatType,
            externalLinkName: "kk_float_nextDown",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-MATH-004: official kotlin.math extension property surface.
        for property in [
            (name: "ulp", receiverType: types.doubleType, returnType: types.doubleType, linkName: "kk_double_ulp"),
            (name: "ulp", receiverType: floatType, returnType: floatType, linkName: "kk_float_ulp"),
        ] {
            registerSyntheticMathExtensionProperty(
                named: property.name,
                packageFQName: kotlinMathPkg,
                receiverType: property.receiverType,
                returnType: property.returnType,
                externalLinkName: property.linkName,
                symbols: symbols,
                interner: interner
            )
        }

    }

    private func registerSyntheticMathTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameterName: String,
        parameterType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticMathTopLevelFunction(
            named: name,
            packageFQName: packageFQName,
            parameters: [(name: parameterName, type: parameterType)],
            returnType: returnType,
            externalLinkName: externalLinkName,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticMathTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: packageFQName,
            parentSymbol: symbols.lookup(fqName: packageFQName),
            parameters: syntheticFunctionParameters(parameters),
            returnType: returnType,
            externalLinkName: externalLinkName,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticMathExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType
                    ),
                    for: getterSymbol
                )
                symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        let getterName = interner.intern("get")
        let getterSymbol = symbols.define(
            kind: .function,
            name: getterName,
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: getterSymbol
        )
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }
}
