/// `java.util.concurrent.TimeUnit` entries in declaration (ordinal) order, which
/// matches `kotlin.time.DurationUnit` so `toTimeUnit()` is an ordinal identity.
private let syntheticTimeUnitEntries = [
    "NANOSECONDS",
    "MICROSECONDS",
    "MILLISECONDS",
    "SECONDS",
    "MINUTES",
    "HOURS",
    "DAYS",
]

extension DataFlowSemaPhase {
    func registerSyntheticPlatformTimeConversionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(path: ["kotlin", "time"], symbols: symbols, interner: interner)

        let kotlinInstantSymbol = ensureClassSymbol(
            named: "Instant",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinDurationSymbol = ensureClassSymbol(
            named: "Duration",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        let kotlinInstantType = types.make(.classType(ClassType(
            classSymbol: kotlinInstantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let kotlinDurationType = types.make(.classType(ClassType(
            classSymbol: kotlinDurationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let javaTimePkg = ensurePackage(path: ["java", "time"], symbols: symbols, interner: interner)
        let javaTimePkgSymbol = symbols.lookup(fqName: javaTimePkg)
        let javaInstantSymbol = ensureClassSymbol(
            named: "Instant",
            in: javaTimePkg,
            symbols: symbols,
            interner: interner
        )
        let javaDurationSymbol = ensureClassSymbol(
            named: "Duration",
            in: javaTimePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaTimePkgSymbol {
            symbols.setParentSymbol(javaTimePkgSymbol, for: javaInstantSymbol)
            symbols.setParentSymbol(javaTimePkgSymbol, for: javaDurationSymbol)
        }

        let javaInstantType = types.make(.classType(ClassType(
            classSymbol: javaInstantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaDurationType = types.make(.classType(ClassType(
            classSymbol: javaDurationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let kotlinJsPkg = ensurePackage(path: ["kotlin", "js"], symbols: symbols, interner: interner)
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)
        let jsDateSymbol = ensureClassSymbol(
            named: "Date",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsDateSymbol)
        }
        let jsDateType = types.make(.classType(ClassType(
            classSymbol: jsDateSymbol,
            args: [],
            nullability: .nonNull
        )))

        // --- STDLIB-TIME-FN-012: DurationUnit.toTimeUnit() -> java.util.concurrent.TimeUnit ---
        // DurationUnit is registered earlier by registerSyntheticDurationStubs; look it up
        // so the receiver type matches the existing synthetic enum surface.
        let durationUnitSymbol = symbols.lookup(fqName: kotlinTimePkg + [interner.intern("DurationUnit")])
        let durationUnitType = durationUnitSymbol.map { symbol in
            types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [],
                nullability: .nonNull
            )))
        }
        let timeUnitSymbol = ensureSyntheticTimeUnitEnumClass(symbols: symbols, interner: interner)
        let timeUnitType = types.make(.classType(ClassType(
            classSymbol: timeUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticTimeUnitEntryTypes(
            enumSymbol: timeUnitSymbol,
            enumType: timeUnitType,
            symbols: symbols
        )

        registerPlatformTimeExtensionFunction(
            named: "toJavaInstant",
            externalLinkName: "kk_instant_to_java_instant",
            receiverType: kotlinInstantType,
            returnType: javaInstantType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toKotlinInstant",
            externalLinkName: "kk_java_instant_to_kotlin_instant",
            receiverType: javaInstantType,
            returnType: kotlinInstantType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toJavaDuration",
            externalLinkName: "kk_duration_to_java_duration",
            receiverType: kotlinDurationType,
            returnType: javaDurationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toKotlinDuration",
            externalLinkName: "kk_java_duration_to_kotlin_duration",
            receiverType: javaDurationType,
            returnType: kotlinDurationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toJSDate",
            externalLinkName: "kk_instant_to_js_date",
            receiverType: kotlinInstantType,
            returnType: jsDateType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toKotlinInstant",
            externalLinkName: "kk_js_date_to_kotlin_instant",
            receiverType: jsDateType,
            returnType: kotlinInstantType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        if let durationUnitType {
            registerPlatformTimeExtensionFunction(
                named: "toTimeUnit",
                externalLinkName: "kk_duration_unit_to_time_unit",
                receiverType: durationUnitType,
                returnType: timeUnitType,
                packageFQName: kotlinTimePkg,
                symbols: symbols,
                interner: interner
            )
        }
    }

    /// Materializes the `java.util.concurrent.TimeUnit` enum surface so
    /// `DurationUnit.toTimeUnit()` has a concrete return type. The entry order
    /// mirrors both `java.util.concurrent.TimeUnit` and `kotlin.time.DurationUnit`
    /// (NANOSECONDS=0 … DAYS=6), which is what makes the conversion an ordinal
    /// identity at runtime.
    private func ensureSyntheticTimeUnitEnumClass(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let javaConcurrentPkg = ensurePackage(
            path: ["java", "util", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let enumName = interner.intern("TimeUnit")
        let enumFQName = javaConcurrentPkg + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if let packageSymbol = symbols.lookup(fqName: javaConcurrentPkg), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            let symbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: javaConcurrentPkg), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        for entry in syntheticTimeUnitEntries {
            let entryName = interner.intern(entry)
            let entryFQName = enumFQName + [entryName]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entryName,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func setSyntheticTimeUnitEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else {
                continue
            }
            symbols.setPropertyType(enumType, for: child)
        }
    }

    private func registerPlatformTimeExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        returnType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes.isEmpty
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }
}
