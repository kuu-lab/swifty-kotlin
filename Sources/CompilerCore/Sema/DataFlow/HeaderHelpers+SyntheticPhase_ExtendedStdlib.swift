import Foundation

/// Extended stdlib batch of synthetic stub registrations from `registerSyntheticDelegateStubs`.
///
/// This Phase covers a 66-call block that previously sat in the middle of the
/// central dispatch: Atomic/Enum/Uuid/Serialization/Networking/Logging/
/// Locale/NumberFormat/Streams/Concurrency/Coroutines/JS-binding stubs.
///
/// Why this file exists: the central dispatch in `HeaderHelpers.swift` is the
/// single largest source of textual merge conflicts in the repo, because every
/// new platform-specific stub PR appends a `registerSyntheticXxx(...)` line to
/// the same long function. Carving stable batches out into Phase files lets
/// parallel branches edit a Phase file rather than fighting over the central
/// dispatch.
///
/// IMPORTANT: the call order inside this function is **identical** to the
/// original middle-section of `registerSyntheticDelegateStubs`. Do NOT reorder
/// lines — Sema golden outputs depend on the registration sequence
/// (some symbols are intentionally re-registered or shadowed by later calls;
/// see e.g. the dual `registerSyntheticJsBooleanInteropStubs` calls preserved
/// here as-is from the original dispatch). When adding a new entry, insert
/// it in the position dictated by any documented dependency; otherwise prefer
/// alphabetical order within the surrounding peer group.
///
/// Companion file: `HeaderHelpers+SyntheticPhase_PlatformAndJS.swift` covers
/// the trailing 28-call Wasm/Js batch. Both Phase files preserve the original
/// dispatch order exactly.
extension DataFlowSemaPhase {
    func registerSyntheticPhase_ExtendedStdlib(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticExperimentalBitwiseStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticEnumStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticAtomicStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticUuidStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticSerializationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticURIStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticURLStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticLocaleConstructorStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticKotlinAnnotationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBigIntegerStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeInvokeStubs(symbols: symbols, interner: interner)
        registerSyntheticThreadLocalStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeSetterStubs(symbols: symbols, interner: interner)
        registerSyntheticConcurrencyStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineCancellationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineIntrinsicsStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticReadWriteLockStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBooleanInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBooleanInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsArrayToListStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeRefRuntimeStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBase64Stubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeConcurrentStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticJsBigIntInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeGetterStubs(symbols: symbols, interner: interner)
        registerSyntheticExperimentalMarkerStubs(symbols: symbols, interner: interner)
    }
}
