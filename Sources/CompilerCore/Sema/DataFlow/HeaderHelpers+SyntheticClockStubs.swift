/// Residual compiler/runtime support for kotlin.time.Clock (STDLIB-TIME-086).
///
/// `Clock` and the public `Clock.System.now()` API are source-backed. This
/// residual file retains only the interface shell and the Companion anchor
/// required by source loading. `Clock` is user-implementable, so `now()` must
/// remain an interface member for virtual dispatch to work.
///
/// `Clock.System` is declared by the bundled source itself as
/// `object System : Clock` in Stdlib/kotlin/time/Clock/Clock.kt, so it gets a
/// real itable entry for `now()` and needs no synthetic anchor here.
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

        _ = ensureClassSymbol(
            named: "Instant",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        let clockSymbol = ensureInterfaceSymbol(
            named: "Clock",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        // Clock.Companion is a public namespace object in the Kotlin API.
        _ = ensureSyntheticCompanionSymbol(
            ownerSymbol: clockSymbol,
            symbols: symbols,
            interner: interner
        )
    }

}
