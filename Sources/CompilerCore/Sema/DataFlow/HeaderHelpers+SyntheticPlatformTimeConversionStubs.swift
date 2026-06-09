/// java.util.concurrent.TimeUnit entry ordering. Mirrors kotlin.time.DurationUnit so that
/// TimeUnit.toDurationUnit() / DurationUnit.toTimeUnit() are 1:1 ordinal mappings.
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

        // --- STDLIB-TIME-FN-006: TimeUnit.toDurationUnit() ---
        // DurationUnit was registered as an enum by registerSyntheticDurationStubs (runs earlier),
        // so ensureClassSymbol resolves the existing enum symbol here.
        let durationUnitSymbol = ensureClassSymbol(
            named: "DurationUnit",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let durationUnitType = types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaConcurrentPkg = ensurePackage(
            path: ["java", "util", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let timeUnitType = ensureSyntheticTimeUnitEnumClass(
            in: javaConcurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toDurationUnit",
            externalLinkName: "kk_time_unit_to_duration_unit",
            receiverType: timeUnitType,
            returnType: durationUnitType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
    }

    /// Registers `java.util.concurrent.TimeUnit` as a synthetic enum whose entries mirror
    /// `kotlin.time.DurationUnit` (same names, same ordinals). Returns the enum's TypeID.
    private func ensureSyntheticTimeUnitEnumClass(
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let enumName = interner.intern("TimeUnit")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

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
            symbols.setPropertyType(enumType, for: entrySymbol)
        }
        return enumType
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
