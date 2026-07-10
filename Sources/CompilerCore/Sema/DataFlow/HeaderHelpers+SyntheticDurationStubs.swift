/// Synthetic stubs for kotlin.time.Duration class, Companion extension properties,
/// and inWhole* accessor properties (STDLIB-582/583/584).
private let syntheticDurationUnitEntries = [
    "NANOSECONDS",
    "MICROSECONDS",
    "MILLISECONDS",
    "SECONDS",
    "MINUTES",
    "HOURS",
    "DAYS",
]

extension DataFlowSemaPhase {
    func registerSyntheticDurationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensureDurationPackageHierarchy(
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TIME-STABLE-008: DurationUnit enum surface ---
        let durationUnitSymbol = ensureSyntheticDurationUnitEnumClass(
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let durationUnitType = types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticDurationUnitEntryTypes(
            enumSymbol: durationUnitSymbol,
            enumType: durationUnitType,
            symbols: symbols
        )

        // --- Duration class symbol ---
        let durationSymbol = ensureClassSymbol(
            named: "Duration",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        _ = ensureDurationCompanionSymbol(
            ownerSymbol: durationSymbol,
            symbols: symbols,
            interner: interner
        )
        guard symbols.companionObjectSymbol(for: durationSymbol) != nil else {
            return
        }
        let durationType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let intType = types.intType
        let longType = types.longType
        let doubleType = types.doubleType
        let stringType = types.stringType
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // --- STDLIB-TIME-STABLE-009: Numeric.toDuration(unit) extension functions ---
        registerDurationFactoryExtensionFunction(
            named: "toDuration",
            externalLinkName: "kk_duration_toDuration_int",
            receiverType: intType,
            parameters: [(name: "unit", type: durationUnitType)],
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionFunction(
            named: "toDuration",
            externalLinkName: "kk_duration_toDuration_long",
            receiverType: longType,
            parameters: [(name: "unit", type: durationUnitType)],
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationFactoryExtensionFunction(
            named: "toDuration",
            externalLinkName: "kk_duration_toDuration_double",
            receiverType: doubleType,
            parameters: [(name: "unit", type: durationUnitType)],
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TIME-STABLE-001: Duration companion constants ---
        // KSP-471: ZERO/INFINITE/parse* are Kotlin source Companion extension
        // properties/functions in Stdlib/kotlin/time/Duration.kt, delegating to
        // the __kk_duration_* bridges registered below. These are receiver-less
        // package-scope functions (registerDurationTopLevelBridgeFunction, not
        // registerDurationMemberMethod): the native kk_duration_zero()-style
        // factories take no argument, so a receiver-typed bridge would wrongly
        // pass the Companion's internal handle as the native call's first arg.
        // Kotlin source calls them without a `this.` prefix.
        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_zero",
            externalLinkName: "kk_duration_zero",
            parameterTypes: [],
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_infinite",
            externalLinkName: "kk_duration_infinite",
            parameterTypes: [],
            returnType: durationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parse",
            externalLinkName: "kk_duration_parse",
            parameterTypes: [stringType],
            returnType: durationType,
            canThrow: true,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parseOrNull",
            externalLinkName: "kk_duration_parseOrNull",
            parameterTypes: [stringType],
            returnType: types.makeNullable(durationType),
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parseIsoString",
            externalLinkName: "kk_duration_parseIsoString",
            parameterTypes: [stringType],
            returnType: durationType,
            canThrow: true,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parseIsoStringOrNull",
            externalLinkName: "kk_duration_parseIsoStringOrNull",
            parameterTypes: [stringType],
            returnType: types.makeNullable(durationType),
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-582/583/584: Duration.inWhole* properties ---
        // KSP-471: inWholeMilliseconds/Microseconds/Seconds/Minutes/Hours/Days are Kotlin
        // source extension properties (Stdlib/kotlin/time/Duration.kt) built on top of
        // inWholeNanoseconds, which stays native (base primitive) below.
        registerDurationMemberProperty(
            named: "inWholeNanoseconds",
            externalLinkName: "kk_duration_inWholeNanoseconds",
            ownerSymbol: durationSymbol,
            returnType: longType,
            symbols: symbols,
            interner: interner
        )

        // --- STDLIB-TIME-082: Duration predicate / absoluteValue ---
        // absoluteValue, isNegative, isPositive, isInfinite are implemented in Kotlin source
        // (Stdlib/kotlin/time/Duration.kt, auto-loaded by LoadSourcesPhase).
        // The __kk_duration_* bridges below are called from that Kotlin source.
        // MIGRATION-TIME-001 complete: direct compat stubs removed; dispatch via Kotlin source.

        // Bridge stubs (called from Stdlib/kotlin/time/Duration.kt)
        registerDurationMemberMethod(
            named: "__kk_duration_absoluteValue",
            externalLinkName: "kk_duration_absoluteValue",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [],
            returnType: durationType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_isNegative",
            externalLinkName: "kk_duration_isNegative",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [],
            returnType: boolType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_isPositive",
            externalLinkName: "kk_duration_isPositive",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [],
            returnType: boolType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_isInfinite",
            externalLinkName: "kk_duration_isInfinite",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [],
            returnType: boolType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        // KSP-471: absoluteValue, isNegative, isPositive, isInfinite, isFinite are all
        // resolved via Kotlin source extension functions/properties in
        // Stdlib/kotlin/time/Duration.kt; isFinite delegates to isInfinite() directly
        // with no native bridge needed.

        // KSP-471: toIsoString and toComponents are Kotlin source (Duration.kt),
        // computed directly from inWholeNanoseconds; no native bridge needed.

        // --- STDLIB-TIME-082: Duration operator bridges (MIGRATION-TIME-001) ---
        // plus, minus, times, div, unaryMinus are implemented in Kotlin source
        // (Stdlib/kotlin/time/Duration.kt, auto-loaded by LoadSourcesPhase).
        // MIGRATION-TIME-001 complete: direct compat stubs removed; dispatch via Kotlin source.

        // Bridge stubs (called from Stdlib/kotlin/time/Duration.kt)
        registerDurationMemberMethod(
            named: "__kk_duration_plus",
            externalLinkName: "kk_duration_plus",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: durationType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_minus",
            externalLinkName: "kk_duration_minus",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: durationType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_times_int",
            externalLinkName: "kk_duration_times_int",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [intType],
            returnType: durationType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_div_int",
            externalLinkName: "kk_duration_div_int",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [intType],
            returnType: durationType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_div_duration",
            externalLinkName: "kk_duration_div_duration",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: doubleType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        registerDurationMemberMethod(
            named: "__kk_duration_unary_minus",
            externalLinkName: "kk_duration_unary_minus",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [],
            returnType: durationType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        // KSP-471: compareTo is a Kotlin source extension operator function
        // (Stdlib/kotlin/time/Duration.kt) delegating to this bridge.
        registerDurationMemberMethod(
            named: "__kk_duration_compareTo",
            externalLinkName: "kk_duration_compareTo",
            ownerSymbol: durationSymbol,
            ownerType: durationType,
            parameterTypes: [durationType],
            returnType: intType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        // KSP-471: Int/Long/Double.{nanoseconds,microseconds,milliseconds,seconds,
        // minutes,hours,days} factory extension properties are now Kotlin source
        // top-level extension properties (Stdlib/kotlin/time/Duration.kt) built on
        // top of the toDuration(unit) bridges registered above. No direct stubs.

        // --- STDLIB-660: TimedValue class ---
        let timedValueSymbol = ensureClassSymbol(
            named: "TimedValue",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let timedValueType = types.make(.classType(ClassType(
            classSymbol: timedValueSymbol,
            args: [],
            nullability: .nonNull
        )))

        // TimedValue.value / TimedValue.duration are implemented in Kotlin
        // source (Stdlib/kotlin/time/TimedValue.kt) as extension properties
        // delegating to these __kk_timedvalue_* bridges (KSP-472).

        // __kk_timedvalue_value(): Any? — generic T erased to Any?
        registerDurationMemberMethod(
            named: "__kk_timedvalue_value",
            externalLinkName: "kk_timedvalue_value",
            ownerSymbol: timedValueSymbol,
            ownerType: timedValueType,
            parameterTypes: [],
            returnType: types.makeNullable(types.anyType),
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        // __kk_timedvalue_duration(): Duration
        registerDurationMemberMethod(
            named: "__kk_timedvalue_duration",
            externalLinkName: "kk_timedvalue_duration",
            ownerSymbol: timedValueSymbol,
            ownerType: timedValueType,
            parameterTypes: [],
            returnType: durationType,
            isOperator: false,
            symbols: symbols,
            interner: interner
        )

        // KSP-471: Long/Double factory extension properties are also Kotlin
        // source (see note above); no direct stubs for those receivers either.
    }

    private func ensureSyntheticDurationUnitEnumClass(
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let enumName = interner.intern("DurationUnit")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if let packageSymbol = symbols.lookup(fqName: packageFQName), packageSymbol != .invalid {
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
            if let packageSymbol = symbols.lookup(fqName: packageFQName), packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        for entry in syntheticDurationUnitEntries {
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

    private func setSyntheticDurationUnitEntryTypes(
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

    private func ensureDurationCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            return companionInfo.fqName
        }

        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        return companionFQName
    }

    private func ensureDurationPackageHierarchy(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinName = interner.intern("kotlin")
        let timeName = interner.intern("time")
        let kotlinFQ: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQ) == nil {
            _ = symbols.define(
                kind: .package, name: kotlinName, fqName: kotlinFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinTimeFQ: [InternedString] = [kotlinName, timeName]
        if symbols.lookup(fqName: kotlinTimeFQ) == nil {
            _ = symbols.define(
                kind: .package, name: timeName, fqName: kotlinTimeFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinTimeFQ
    }

    // MARK: - Duration member method registration (STDLIB-TIME-082)

    private func registerDurationMemberMethod(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        isOperator: Bool = true,
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]

        // Check for existing registration with matching parameter types
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .function,
                  let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if isOperator {
                symbols.insertFlags([.operatorFunction], for: existing)
            }
            if canThrow {
                symbols.insertFlags([.throwingFunction], for: existing)
            }
            if let existingSignature = symbols.functionSignature(for: existing),
               existingSignature.receiverType != ownerType
            {
                symbols.setFunctionSignature(
                    existingSignature.withReceiverType(ownerType),
                    for: existing
                )
            }
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if isOperator {
            flags.insert(.operatorFunction)
        }
        if canThrow {
            flags.insert(.throwingFunction)
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        // Build parameter symbols
        var paramSymbols: [SymbolID] = []
        var paramDefaults: [Bool] = []
        var paramVarargs: [Bool] = []
        for (idx, paramType) in parameterTypes.enumerated() {
            let paramName = interner.intern("p\(idx)")
            let paramFQName = functionFQName + [paramName]
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: paramFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
            paramDefaults.append(false)
            paramVarargs.append(false)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                canThrow: canThrow,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: paramDefaults,
                valueParameterIsVararg: paramVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    private func registerDurationMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
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
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }

    private func registerDurationFactoryExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        packageFQName: [InternedString],
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

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        parameterTypes.reserveCapacity(parameters.count)
        parameterSymbols.reserveCapacity(parameters.count)
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
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    /// Registers a receiver-less bridge function at package scope. Unlike
    /// registerDurationMemberMethod (which passes the receiver's internal handle
    /// as the native call's first argument), this has no receiver at all, so it
    /// matches native factory functions like kk_duration_zero() that take no
    /// argument. Kotlin source calls it without a `this.` prefix.
    private func registerDurationTopLevelBridgeFunction(
        named name: String,
        externalLinkName: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        canThrow: Bool = false,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil && signature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if canThrow {
                symbols.insertFlags([.throwingFunction], for: existing)
            }
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if canThrow {
            flags.insert(.throwingFunction)
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var paramSymbols: [SymbolID] = []
        for (idx, paramType) in parameterTypes.enumerated() {
            let paramName = interner.intern("p\(idx)")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: returnType,
                canThrow: canThrow,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: functionSymbol
        )
    }
}

private extension FunctionSignature {
    func withReceiverType(_ receiverType: TypeID?) -> FunctionSignature {
        FunctionSignature(
            receiverType: receiverType,
            parameterTypes: parameterTypes,
            returnType: returnType,
            isSuspend: isSuspend,
            canThrow: canThrow,
            valueParameterSymbols: valueParameterSymbols,
            valueParameterHasDefaultValues: valueParameterHasDefaultValues,
            valueParameterIsVararg: valueParameterIsVararg,
            typeParameterSymbols: typeParameterSymbols,
            reifiedTypeParameterIndices: reifiedTypeParameterIndices,
            typeParameterUpperBounds: typeParameterUpperBounds,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList,
            classTypeParameterCount: classTypeParameterCount
        )
    }
}
