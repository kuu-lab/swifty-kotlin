
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
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "load",
            returnType: nativePtrType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "store",
            returnType: types.unitType,
            parameters: [(name: "value", type: nativePtrType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "exchange",
            returnType: nativePtrType,
            parameters: [(name: "new", type: nativePtrType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: nativePtrType,
            parameters: [(name: "newValue", type: nativePtrType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expect", type: nativePtrType),
                (name: "update", type: nativePtrType),
            ],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "compareAndExchange",
            returnType: nativePtrType,
            parameters: [
                (name: "expect", type: nativePtrType),
                (name: "update", type: nativePtrType),
            ],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        let transformType = types.make(.functionType(FunctionType(
            params: [nativePtrType],
            returnType: nativePtrType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "fetchAndUpdate",
            returnType: nativePtrType,
            parameters: [(name: "transform", type: transformType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
    }
}
