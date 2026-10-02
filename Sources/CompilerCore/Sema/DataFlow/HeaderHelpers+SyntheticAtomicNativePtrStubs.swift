
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
        let nativePtrType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "NativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
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

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            parameters: [(name: "value", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: nativePtrType,
            symbols: symbols,
            interner: interner
        )
        // KSP-1121: `load` / `store` / `exchange` / `getAndSet` /
        // `compareAndSet` / `compareAndExchange` moved to the source-backed
        // extensions in `Stdlib/kotlin/concurrent/atomics/AtomicNativePtr/`
        // (there is no `__kk_atomic_native_ptr_*` runtime family, so member
        // stubs would only emit unresolved bare-symbol calls). The bundled
        // declarations win member resolution via the atomic-migration
        // extension fallback; `value` stays a member because it is the
        // field-backed storage those extensions delegate to.
    }
}
