/// Synthetic stubs for kotlin.time.Clock (STDLIB-TIME-086).
///
/// Registers `kotlin.time.Clock` interface with its instance method `now()`
/// as a direct native bridge (kk_clock_now). Clock is a user-implementable
/// interface, so `now()` must remain a real class member for virtual dispatch
/// to work.
///
/// `Clock.System` is created as a nested object so that the bundled Kotlin
/// source extension `Clock.System.now()` in Stdlib/kotlin/time/Clock.kt can
/// resolve. The Clock.System.now() factory itself is implemented in Kotlin
/// source and delegates to `kk_clock_system_now` via a `@KsSymbolName`
/// external declaration.
///
/// kotlin.time.Instant itself is registered by
/// HeaderHelpers+SyntheticInstantStubs.swift; this file only re-resolves the
/// existing Instant symbol to use as the return type of Clock.now().
extension DataFlowSemaPhase {
    func registerSyntheticClockStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(
            path: ["kotlin", "time"],
            symbols: symbols,
            interner: interner
        )

        // MARK: - Instant class (registered by registerSyntheticInstantStubs)

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

        // MARK: - Clock interface

        let clockSymbol = ensureClassSymbol(
            named: "Clock",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let clockType = types.make(.classType(ClassType(
            classSymbol: clockSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Clock.now() -> Instant (interface method)
        registerClockMemberFunction(
            named: "now",
            externalLinkName: "kk_clock_now",
            ownerSymbol: clockSymbol,
            ownerType: clockType,
            parameters: [],
            returnType: instantType,
            symbols: symbols,
            interner: interner
        )

        // --- Clock.System nested object ---
        // Created so the bundled Kotlin-source extension Clock.System.now()
        // in Stdlib/kotlin/time/Clock.kt can resolve.
        _ = ensureClockNestedObject(
            named: "System",
            ownerSymbol: clockSymbol,
            ownerFQName: kotlinTimePkg + [interner.intern("Clock")],
            symbols: symbols,
            interner: interner
        )
    }

    /// Creates a nested object (e.g. Clock.System) under an existing class symbol.
    /// Returns the FQ name of the newly created (or existing) object.
    private func ensureClockNestedObject(
        named objectName: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let interned = interner.intern(objectName)
        let fqName = ownerFQName + [interned]
        if let existing = symbols.lookup(fqName: fqName) {
            if let info = symbols.symbol(existing) {
                return info.fqName
            }
        }
        let objectSymbol = symbols.define(
            kind: .object,
            name: interned,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: objectSymbol)
        return fqName
    }

    private func registerClockMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        isOperator: Bool = false
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) == nil else {
            return
        }
        var flags: SymbolFlags = [.synthetic]
        if isOperator { flags.insert(.operatorFunction) }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        var parameterTypes: [TypeID] = []
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
            parameterTypes.append(parameter.type)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
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
