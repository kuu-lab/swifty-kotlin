/// Synthetic stubs for kotlin.time.Instant class (STDLIB-TIME-083).
///
/// Creates the `Instant.Companion` synthetic object so that bundled Kotlin
/// source extensions on the companion (`Instant.now()`, `fromEpochMilliseconds`)
/// can resolve. The factories themselves are implemented in
/// `Stdlib/kotlin/time/Instant.kt` and delegate to `kk_instant_now` /
/// `kk_instant_from_epoch_millis` via `@KsSymbolName` external declarations.
///
/// Also registers `__kk_instant_*` bridge methods used by
/// `Stdlib/kotlin/time/Instant.kt` to implement `epochSeconds`,
/// `nanosecondsOfSecond`, `isDistantPast`, `isDistantFuture`, `plus`/`minus`
/// (Duration), `compareTo`, and `minus` (Instant, returning Duration) as
/// Kotlin-source extension properties/functions/operators (KSP-472).
/// `elapsed()` has no dedicated bridge; it reuses the same
/// `__kk_instant_until` bridge as the Instant-Instant `minus` overload,
/// written directly in Kotlin source as `this.__kk_instant_until(Instant.now())`.
extension DataFlowSemaPhase {
    func registerSyntheticInstantStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(
            path: ["kotlin", "time"],
            symbols: symbols,
            interner: interner
        )

        // --- Instant class symbol ---
        let instantSymbol = ensureClassSymbol(
            named: "Instant",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        let instantType = types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Duration type for arithmetic
        let durationSymbol = ensureClassSymbol(
            named: "Duration",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let durationType = types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let longType = types.longType
        let intType = types.intType
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // --- Companion object for bundled Kotlin-source extensions ---
        // Instant.now() / fromEpochMilliseconds() are implemented in
        // Stdlib/kotlin/time/Instant.kt. The companion object must exist so
        // extension functions on Instant.Companion can resolve.
        _ = ensureInstantCompanionSymbol(
            ownerSymbol: instantSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- KSP-472: bridge methods for Stdlib/kotlin/time/Instant.kt ---
        // Called as `this.__kk_instant_*(...)` from Kotlin source; the
        // public API (epochSeconds, nanosecondsOfSecond, isDistantPast,
        // isDistantFuture, plus, minus (Duration and Instant overloads),
        // compareTo) is defined there as extension properties/functions/
        // operators.

        registerInstantInstanceMethod(
            named: "__kk_instant_epoch_seconds",
            externalLinkName: "kk_instant_epoch_seconds",
            returnType: longType,
            parameters: [],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        registerInstantInstanceMethod(
            named: "__kk_instant_nano_of_second",
            externalLinkName: "kk_instant_nano_of_second",
            returnType: intType,
            parameters: [],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        registerInstantInstanceMethod(
            named: "__kk_instant_is_distant_past",
            externalLinkName: "kk_instant_is_distant_past",
            returnType: boolType,
            parameters: [],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        registerInstantInstanceMethod(
            named: "__kk_instant_is_distant_future",
            externalLinkName: "kk_instant_is_distant_future",
            returnType: boolType,
            parameters: [],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        registerInstantInstanceMethod(
            named: "__kk_instant_plus_duration",
            externalLinkName: "kk_instant_plus_duration",
            returnType: instantType,
            parameters: [(name: "duration", type: durationType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        registerInstantInstanceMethod(
            named: "__kk_instant_minus_duration",
            externalLinkName: "kk_instant_minus_duration",
            returnType: instantType,
            parameters: [(name: "duration", type: durationType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        registerInstantInstanceMethod(
            named: "__kk_instant_compare",
            externalLinkName: "kk_instant_compare",
            returnType: intType,
            parameters: [(name: "other", type: instantType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )

        registerInstantInstanceMethod(
            named: "__kk_instant_until",
            externalLinkName: "kk_instant_until",
            returnType: durationType,
            parameters: [(name: "other", type: instantType)],
            ownerSymbol: instantSymbol,
            ownerType: instantType,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureInstantCompanionSymbol(
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

    private func registerInstantInstanceMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        isOperator: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map { $0.type } &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }
        let memberFlags: SymbolFlags = isOperator ? [.synthetic, .operatorFunction] : [.synthetic]
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: memberFlags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map { $0.type },
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }
}
