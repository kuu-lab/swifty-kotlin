
/// Synthetic Kotlin/Native metaprogramming and C interop stubs.
extension DataFlowSemaPhase {
    func registerSyntheticNativeInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticCInteropStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeIdentityHashCodeStub(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeUnhandledExceptionHookStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeByteArrayAccessorStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
