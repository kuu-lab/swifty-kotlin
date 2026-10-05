/// Synthetic bridges retained for kotlin.time.Duration's native parsing and
/// arithmetic compatibility surface.

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

        // --- STDLIB-TIME-STABLE-008: DurationUnit enum anchor ---
        // The enum entries are declared by bundled DurationUnit.kt. Keep only
        // the nominal shell here so source collection can reuse it.
        _ = ensureSyntheticDurationUnitEnumClass(
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
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
        let longType = types.longType
        let stringType = types.stringType

        // --- STDLIB-TIME-STABLE-001: Duration companion constants ---
        // KUU-1093: `Duration` now implements `Comparable<Duration>`, so every
        // Duration value is a real boxed object (interface-implementing value
        // classes keep their boxed representation; see
        // `effectiveValueClassUnderlyingType`). The kk_duration_* cdecls,
        // however, speak raw Int64 nanosecond payloads — a raw `Duration`-typed
        // bridge return would be a bogus object reference. The parse bridges
        // therefore return `Long`/`Long?` (nanoseconds), and Kotlin source in
        // Stdlib/kotlin/time/Duration.kt wraps them in `Duration(...)`. The
        // former __kk_duration_zero/infinite and member bridges
        // (absoluteValue/isNegative/isPositive/isInfinite/plus/minus/times_int/
        // div_int/div_duration/unary_minus/compareTo) were dropped: every
        // operation they backed is now resolved via Kotlin source, and leaving
        // raw-Int64-typed-as-Duration stubs registered would be a latent
        // wrong-ABI hazard.
        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parse",
            externalLinkName: "kk_duration_parse",
            parameterTypes: [stringType],
            returnType: longType,
            canThrow: true,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parseOrNull",
            externalLinkName: "kk_duration_parseOrNull",
            parameterTypes: [stringType],
            returnType: types.makeNullable(longType),
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parseIsoString",
            externalLinkName: "kk_duration_parseIsoString",
            parameterTypes: [stringType],
            returnType: longType,
            canThrow: true,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        registerDurationTopLevelBridgeFunction(
            named: "__kk_duration_parseIsoStringOrNull",
            externalLinkName: "kk_duration_parseIsoStringOrNull",
            parameterTypes: [stringType],
            returnType: types.makeNullable(longType),
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        // KSP-471: Int/Long/Double.{nanoseconds,microseconds,milliseconds,seconds,
        // minutes,hours,days} factory extension properties are now Kotlin source
        // top-level extension properties (Stdlib/kotlin/time/Duration.kt) built on
        // top of the toDuration(unit) bridges registered above. No direct stubs.

        // KSP-1497: TimedValue is declared as a bundled Kotlin data class.
        // Its constructor, stored properties, and synthesized members use the
        // ordinary source-backed data-class pipeline, with no runtime bridge.

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

        return enumSymbol
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
        // Reuse a companion nominal already imported from a shared stdlib
        // artifact; otherwise source-backed companion extensions would carry
        // a receiver type tied to a duplicate synthetic symbol.
        if let importedCompanion = symbols.lookupAll(fqName: companionFQName)
            .compactMap({ symbols.symbol($0) })
            .first(where: { $0.kind == .object || $0.kind == .class || $0.kind == .interface })
        {
            symbols.setParentSymbol(ownerSymbol, for: importedCompanion.id)
            symbols.setCompanionObjectSymbol(importedCompanion.id, for: ownerSymbol)
            return companionFQName
        }
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

extension DataFlowSemaPhase {

    func registerSyntheticDurationCompatibilityStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // --- kotlin.time package (STDLIB-230/231/585) ---
        let kotlinTimePkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("time")],
            symbols: symbols
        )

        // Register synthetic Duration class (STDLIB-585)
        let durationName = interner.intern("Duration")
        let durationFQName = kotlinTimePkg + [durationName]
        let durationSymbol: SymbolID = if let existing = symbols.lookup(fqName: durationFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: durationName,
                fqName: durationFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: kotlinTimePkg) {
            symbols.setParentSymbol(packageSymbol, for: durationSymbol)
        }

        let durationClassType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(durationClassType, for: durationSymbol)

        // Register Duration.inWholeNanoseconds property (returns Long)
        registerSyntheticDurationMember(
            named: "inWholeNanoseconds",
            externalLinkName: "kk_duration_inWholeNanoseconds",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.longType,
            symbols: symbols,
            interner: interner,
            isProperty: true
        )

        // Register Duration.toString() (returns String)
        registerSyntheticDurationMember(
            named: "toString",
            externalLinkName: "kk_duration_toString",
            durationSymbol: durationSymbol,
            durationFQName: durationFQName,
            receiverType: durationClassType,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // measureTime / measureTimedValue live in bundled Kotlin source
        // (Stdlib/kotlin/time/MeasureTime.kt).
    }

    private func registerSyntheticDurationMember(
        named name: String,
        externalLinkName: String,
        durationSymbol: SymbolID,
        durationFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        isProperty: Bool = false
    ) {
        let memberName = interner.intern(name)
        let memberFQName = durationFQName + [memberName]

        // If a symbol already exists at this fqName, ensure its linkage
        // metadata is up-to-date (mirroring registerSyntheticTopLevelFunction).
        if let existing = symbols.lookup(fqName: memberFQName) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if isProperty {
                symbols.setPropertyType(returnType, for: existing)
            }
            return
        }

        if isProperty {
            let memberSymbol = symbols.define(
                kind: .property,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(durationSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setPropertyType(returnType, for: memberSymbol)
        } else {
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(durationSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }
    }
}
