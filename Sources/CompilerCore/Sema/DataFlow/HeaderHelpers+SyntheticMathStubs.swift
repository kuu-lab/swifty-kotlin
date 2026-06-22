/// Synthetic fallback declarations for the official kotlin.math surface used by Sema.
/// Source stdlib declarations take precedence when imported; these stubs keep
/// no-stdlib-search compiler tests and standalone front-end analysis resolvable.
extension DataFlowSemaPhase {
    func registerSyntheticMathStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinMathPkg = ensurePackage(path: ["kotlin", "math"], symbols: symbols, interner: interner)
        let double = types.doubleType
        let float = types.floatType
        let int = types.intType
        let long = types.longType
        let uint = types.uintType
        let ulong = types.ulongType

        let unaryFloatingLinks: [(String, String, String)] = [
            ("acos", "kk_math_acos", "kk_math_acos_float"),
            ("acosh", "kk_math_acosh", "kk_math_acosh_float"),
            ("asin", "kk_math_asin", "kk_math_asin_float"),
            ("asinh", "kk_math_asinh", "kk_math_asinh_float"),
            ("atan", "kk_math_atan", "kk_math_atan_float"),
            ("atanh", "kk_math_atanh", "kk_math_atanh_float"),
            ("cbrt", "kk_math_cbrt", "kk_math_cbrt_float"),
            ("ceil", "kk_math_ceil", "kk_math_ceil_float"),
            ("cos", "kk_math_cos", "kk_math_cos_float"),
            ("cosh", "kk_math_cosh", "kk_math_cosh_float"),
            ("exp", "kk_math_exp", "kk_math_exp_float"),
            ("expm1", "kk_math_expm1", "kk_math_expm1_float"),
            ("floor", "kk_math_floor", "kk_math_floor_float"),
            ("ln", "kk_math_ln", "kk_math_ln_float"),
            ("ln1p", "kk_math_ln1p", "kk_math_ln1p_float"),
            ("log10", "kk_math_log10", "kk_math_log10_float"),
            ("log2", "kk_math_log2", "kk_math_log2_float"),
            ("round", "kk_math_round", "kk_math_round_float"),
            ("sign", "kk_math_sign", "kk_math_sign_float"),
            ("sin", "kk_math_sin", "kk_math_sin_float"),
            ("sinh", "kk_math_sinh", "kk_math_sinh_float"),
            ("sqrt", "kk_math_sqrt", "kk_math_sqrt_float"),
            ("tan", "kk_math_tan", "kk_math_tan_float"),
            ("tanh", "kk_math_tanh", "kk_math_tanh_float"),
            ("truncate", "kk_math_truncate", "kk_math_truncate_float"),
        ]
        for (name, doubleLink, floatLink) in unaryFloatingLinks {
            registerSyntheticMathFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                parameters: [(name: "x", type: double)],
                returnType: double,
                externalLinkName: doubleLink,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticMathFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                parameters: [(name: "x", type: float)],
                returnType: float,
                externalLinkName: floatLink,
                symbols: symbols,
                interner: interner
            )
        }

        for (name, parameterType, returnType, link) in [
            ("abs", int, int, "kk_math_abs_int"),
            ("abs", long, long, "kk_math_abs_long"),
            ("abs", double, double, "kk_math_abs"),
            ("abs", float, float, "kk_math_abs_float"),
            ("roundToInt", double, int, "kk_double_roundToInt"),
            ("roundToInt", float, int, "kk_float_roundToInt"),
            ("roundToLong", double, long, "kk_double_roundToLong"),
            ("roundToLong", float, long, "kk_float_roundToLong"),
            ("ulp", double, double, "kk_double_ulp"),
            ("ulp", float, float, "kk_float_ulp"),
            ("nextUp", double, double, "kk_double_nextUp"),
            ("nextUp", float, float, "kk_float_nextUp"),
            ("nextDown", double, double, "kk_double_nextDown"),
            ("nextDown", float, float, "kk_float_nextDown"),
        ] {
            registerSyntheticMathFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                parameters: [(name: "x", type: parameterType)],
                returnType: returnType,
                externalLinkName: link,
                symbols: symbols,
                interner: interner
            )
        }

        for (name, parameterType, returnType, link) in [
            ("max", double, double, "kk_math_max"),
            ("max", float, float, "kk_math_max_float"),
            ("max", int, int, "kk_math_max_int"),
            ("max", long, long, "kk_math_max_long"),
            ("max", uint, uint, "kk_math_max_uint"),
            ("max", ulong, ulong, "kk_math_max_ulong"),
            ("min", double, double, "kk_math_min"),
            ("min", float, float, "kk_math_min_float"),
            ("min", int, int, "kk_math_min_int"),
            ("min", long, long, "kk_math_min_long"),
            ("min", uint, uint, "kk_math_min_uint"),
            ("min", ulong, ulong, "kk_math_min_ulong"),
        ] {
            registerSyntheticMathFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                parameters: [(name: "a", type: parameterType), (name: "b", type: parameterType)],
                returnType: returnType,
                externalLinkName: link,
                symbols: symbols,
                interner: interner
            )
        }

        for (name, parameterType, returnType, link) in [
            ("atan2", double, double, "kk_math_atan2"),
            ("atan2", float, float, "kk_math_atan2_float"),
            ("hypot", double, double, "kk_math_hypot"),
            ("hypot", float, float, "kk_math_hypot_float"),
            ("log", double, double, "kk_math_log"),
            ("log", float, float, "kk_math_log_float"),
            ("pow", double, double, "kk_math_pow"),
            ("pow", float, float, "kk_math_pow_float"),
        ] {
            registerSyntheticMathFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                parameters: [(name: "x", type: parameterType), (name: "y", type: parameterType)],
                returnType: returnType,
                externalLinkName: link,
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticMathFunction(
            named: "pow",
            packageFQName: kotlinMathPkg,
            parameters: [(name: "x", type: double), (name: "n", type: int)],
            returnType: double,
            externalLinkName: "kk_math_pow_int",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathFunction(
            named: "pow",
            packageFQName: kotlinMathPkg,
            parameters: [(name: "x", type: float), (name: "n", type: int)],
            returnType: float,
            externalLinkName: "kk_math_pow_float_int",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathProperty(
            named: "PI",
            packageFQName: kotlinMathPkg,
            returnType: double,
            externalLinkName: "kk_math_PI",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathProperty(
            named: "E",
            packageFQName: kotlinMathPkg,
            returnType: double,
            externalLinkName: "kk_math_E",
            symbols: symbols,
            interner: interner
        )

        for (name, receiverType, returnType, link) in [
            ("IEEErem", double, double, "kk_math_IEEErem"),
            ("IEEErem", float, float, "kk_math_IEEErem_float"),
            ("nextTowards", double, double, "kk_math_nextTowards"),
            ("nextTowards", float, float, "kk_math_nextTowards_float"),
            ("pow", double, double, "kk_math_pow"),
            ("pow", float, float, "kk_math_pow_float"),
        ] {
            registerSyntheticMathFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                receiverType: receiverType,
                parameters: [(name: "other", type: receiverType)],
                returnType: returnType,
                externalLinkName: link,
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticMathFunction(
            named: "pow",
            packageFQName: kotlinMathPkg,
            receiverType: double,
            parameters: [(name: "n", type: int)],
            returnType: double,
            externalLinkName: "kk_math_pow_int",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathFunction(
            named: "pow",
            packageFQName: kotlinMathPkg,
            receiverType: float,
            parameters: [(name: "n", type: int)],
            returnType: float,
            externalLinkName: "kk_math_pow_float_int",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathFunction(
            named: "withSign",
            packageFQName: kotlinMathPkg,
            receiverType: double,
            parameters: [(name: "sign", type: double)],
            returnType: double,
            externalLinkName: "kk_math_withSign",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathFunction(
            named: "withSign",
            packageFQName: kotlinMathPkg,
            receiverType: double,
            parameters: [(name: "sign", type: int)],
            returnType: double,
            externalLinkName: "kk_math_withSign_int",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathFunction(
            named: "withSign",
            packageFQName: kotlinMathPkg,
            receiverType: float,
            parameters: [(name: "sign", type: float)],
            returnType: float,
            externalLinkName: "kk_math_withSign_float",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathFunction(
            named: "withSign",
            packageFQName: kotlinMathPkg,
            receiverType: float,
            parameters: [(name: "sign", type: int)],
            returnType: float,
            externalLinkName: "kk_math_withSign_float_int",
            symbols: symbols,
            interner: interner
        )

        for (name, receiverType, returnType, link) in [
            ("absoluteValue", double, double, "kk_math_abs"),
            ("absoluteValue", float, float, "kk_math_abs_float"),
            ("absoluteValue", int, int, "kk_math_abs_int"),
            ("absoluteValue", long, long, "kk_math_abs_long"),
            ("sign", double, double, "kk_math_sign"),
            ("sign", float, float, "kk_math_sign_float"),
            ("sign", int, int, "kk_math_sign_int"),
            ("sign", long, int, "kk_math_sign_long"),
            ("ulp", double, double, "kk_double_ulp"),
            ("ulp", float, float, "kk_float_ulp"),
        ] {
            registerSyntheticMathExtensionProperty(
                named: name,
                packageFQName: kotlinMathPkg,
                receiverType: receiverType,
                returnType: returnType,
                externalLinkName: link,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticMathFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID? = nil,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
            let existingFlags = symbols.symbol(existing)?.flags ?? []
            if existingFlags.contains(.synthetic) && !existingFlags.contains(.importedLibrary) {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            return
        }
        if hasSourceOrImportedLibrarySymbol(fqName: functionFQName, kind: .function, symbols: symbols) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticMathProperty(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            let existingFlags = symbols.symbol(existing)?.flags ?? []
            if existingFlags.contains(.synthetic) && !existingFlags.contains(.importedLibrary) {
                symbols.setExternalLinkName(externalLinkName, for: existing)
                symbols.setPropertyType(returnType, for: existing)
            }
            return
        }
        if hasSourceOrImportedLibrarySymbol(fqName: propertyFQName, kind: .property, symbols: symbols) {
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
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
            let existingFlags = symbols.symbol(existing)?.flags ?? []
            let shouldPatchSynthetic = existingFlags.contains(.synthetic) && !existingFlags.contains(.importedLibrary)
            if shouldPatchSynthetic {
                symbols.setExternalLinkName(externalLinkName, for: existing)
                symbols.setPropertyType(returnType, for: existing)
                if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                    symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: receiverType,
                            parameterTypes: [],
                            returnType: returnType
                        ),
                        for: getterSymbol
                    )
                }
            }
            return
        }
        if hasSourceOrImportedLibrarySymbol(fqName: propertyFQName, kind: .property, symbols: symbols) {
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
