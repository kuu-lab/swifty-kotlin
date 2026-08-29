
/// Synthetic stdlib stubs for kotlin.concurrent atomic and lock types.
/// This file holds only the top-level entry point that orchestrates
/// registration; the actual registration logic is split by
/// responsibility across sibling files (KSP-695):
///  - `HeaderHelpers+SyntheticAtomicRegistrationHelpers.swift`: shared
///    constructor/member/property registration primitives
///  - `HeaderHelpers+SyntheticAtomicScalarStubs.swift`: AtomicInt/
///    AtomicLong/AtomicBoolean/AtomicReference (incl. the
///    `java.util.concurrent.atomic.AtomicInteger` direct-construction
///    surface, which shares the `kk_atomic_int_*` box/prefix and is a
///    live, tested API — see `Stdlib/kotlin/concurrent/AtomicMigration.kt`)
///  - `HeaderHelpers+SyntheticAtomicArrayStubs.swift`: AtomicIntArray/
///    AtomicLongArray/AtomicArray<T> and their factories
///  - `HeaderHelpers+SyntheticAtomicPackageStubs.swift`:
///    `kotlin.concurrent.atomics` package scaffolding (annotation,
///    MemoryOrder enum, type aliases)
///  - `HeaderHelpers+SyntheticAtomicNativePtrStubs.swift`: AtomicNativePtr
extension DataFlowSemaPhase {
    func registerSyntheticAtomicStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let concurrentPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let atomicsPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent", "atomics"],
            symbols: symbols,
            interner: interner
        )

        let intType = types.intType
        let longType = types.longType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let unitType = types.unitType

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicInt",
            constructorLinkName: "kk_atomic_int_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicLong",
            constructorLinkName: "kk_atomic_long_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicBoolean",
            constructorLinkName: "kk_atomic_bool_create",
            valueType: boolType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_bool",
            includeArithmetic: false,
            includeGetAndSetAlias: true,
            includeCompareAndSet: false,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicReferenceStubs(
            ownerPackage: concurrentPkg,
            ownerPackageSymbol: symbols.lookup(fqName: concurrentPkg) ?? .invalid,
            symbols: symbols,
            types: types,
            interner: interner,
            externalLinkPrefix: "kk_atomic_ref"
        )
        registerAtomicArrayFamily(
            packageFQName: concurrentPkg,
            className: "AtomicIntArray",
            constructorLinkName: "kk_atomic_int_array_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int_array",
            includeArithmetic: true,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicArrayFamily(
            packageFQName: concurrentPkg,
            className: "AtomicLongArray",
            constructorLinkName: "kk_atomic_long_array_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long_array",
            includeArithmetic: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        let memoryOrderSymbol = ensureAtomicMemoryOrderEnum(
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let memoryOrderType = types.make(.classType(ClassType(
            classSymbol: memoryOrderSymbol,
            args: [],
            nullability: .nonNull
        )))
        setAtomicEnumEntryTypes(
            enumSymbol: memoryOrderSymbol,
            enumType: memoryOrderType,
            symbols: symbols
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicInt",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicInt",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicLong",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicLong",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicBoolean",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicBoolean",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicReference",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicReference",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types,
            typeParameterNames: ["T"]
        )
        registerAtomicNativePtrSurface(
            packageFQName: atomicsPkg,
            packageSymbol: symbols.lookup(fqName: atomicsPkg),
            symbols: symbols,
            types: types,
            interner: interner
        )
        // Directly-constructible java.util.concurrent.atomic.AtomicInteger, backed by the
        // same kk_atomic_int_* box as kotlin.concurrent.AtomicInt.
        let javaAtomicPkg = ensureAtomicPackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        registerAtomicScalarFamily(
            packageFQName: javaAtomicPkg,
            className: "AtomicInteger",
            constructorLinkName: "kk_atomic_int_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )


        registerAtomicArrayFamily(
            packageFQName: atomicsPkg,
            className: "AtomicIntArray",
            constructorLinkName: "kk_atomic_int_array_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int_array",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )


        registerAtomicArrayFamily(
            packageFQName: atomicsPkg,
            className: "AtomicLongArray",
            constructorLinkName: "kk_atomic_long_array_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long_array",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeAddAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )


        registerAtomicRefArrayStub(
            packageFQName: atomicsPkg,
            boolType: boolType,
            unitType: unitType,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicArrayOfNullsFactory(
            packageFQName: atomicsPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicArrayOfFactory(
            packageFQName: atomicsPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- Lock --
        let lockSymbol = ensureClassSymbol(
            named: "Lock",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let lockType = types.make(.classType(ClassType(
            classSymbol: lockSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(lockType, for: lockSymbol)
        // KSP-677: Lock.withLock is migrated to Kotlin source
        // (Stdlib/kotlin/concurrent/Lock.kt) delegating to the demoted
        // __kk_lock_withLock bridge. Only the Lock class symbol is kept so the
        // Kotlin external declaration can reference it as a type.

    }
}
