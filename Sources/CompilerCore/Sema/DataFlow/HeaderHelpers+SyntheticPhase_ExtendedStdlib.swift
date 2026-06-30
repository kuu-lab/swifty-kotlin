import Foundation

/// Extended stdlib batch of synthetic stub registrations from `registerSyntheticDelegateStubs`.
///
/// This Phase covers a subset of the original middle-section of the central
/// dispatch: Atomic/Enum/Serialization/Coroutines/Native stubs.
/// JS/Wasm/JVM-specific registrations (Uuid, URI/URL, Locale, BigInteger,
/// ThreadLocal, Concurrency, ReadWriteLock, JsArray, ExperimentalMarker) have
/// been removed as they are not applicable to the Native target.
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
/// (some symbols are intentionally re-registered or shadowed by later calls).
/// When adding a new entry, insert it in the position dictated by any documented
/// dependency; otherwise prefer alphabetical order within the surrounding peer group.
///
/// Companion file: `HeaderHelpers+SyntheticPhase_PlatformAndJS.swift` covers
/// the trailing Wasm/JS batch.
extension DataFlowSemaPhase {
    func registerSyntheticPhase_ExtendedStdlib(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticExperimentalBitwiseStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticEnumStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticAtomicStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticSerializationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticKotlinAnnotationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeInteropStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeInvokeStubs(symbols: symbols, interner: interner)
        registerSyntheticNativeSetterStubs(symbols: symbols, interner: interner)
        registerSyntheticCoroutineCancellationStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticCoroutineIntrinsicsStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeRefRuntimeStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticBase64Stubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeConcurrentStubs(symbols: symbols, types: types, interner: interner)
        registerSyntheticNativeGetterStubs(symbols: symbols, interner: interner)
    }
}
