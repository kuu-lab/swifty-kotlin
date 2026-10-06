
/// `kotlin.concurrent.atomics.AtomicNativePtr`, built on the shared
/// NativeConcurrent registration helpers (see
/// `HeaderHelpers+SyntheticNativeConcurrentCommon.swift`). Kept apart from
/// the rest of the Atomic family since it depends on `kotlinx.cinterop`
/// and may reclassify independently of the pure-Kotlin atomic surface.
extension DataFlowSemaPhase {
    func registerAtomicNativePtrSurface(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let classSymbol = ensureClassSymbol(
            named: "AtomicNativePtr",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        let ownerType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: classSymbol)

        // The constructor and field live in bundled Kotlin source. A
        // synthetic constructor here has no body or runtime link name and
        // emits a reference to the undefined `AtomicNativePtr` symbol.
        // Receiver operations are source-backed extensions in
        // `Stdlib/kotlin/concurrent/atomics/AtomicNativePtr/`; synthetic member
        // stubs would also emit unresolved bare-symbol calls.
    }
}
