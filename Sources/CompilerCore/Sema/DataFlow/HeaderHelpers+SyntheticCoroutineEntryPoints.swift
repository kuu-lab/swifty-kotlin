extension DataFlowSemaPhase {
    // STDLIB-CORO-BUG-04: this used to also register a `Job.cancel()`
    // extension function under kotlin.coroutines.cancellation, duplicating
    // the member declared in registerSyntheticCoroutineStubs (same receiver,
    // arity, and external link name) and making `job.cancel()` ambiguous.
    // Removed; kept as a no-op since the SyntheticStubRegistryEntry bucket
    // table references this function by name.
    func registerSyntheticCoroutineCancellationStubs() {}

    func registerSyntheticCoroutineIntrinsicsStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinCoroutinesPkg = ensureSyntheticCoroutinePackage(
            kotlinPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let intrinsicsPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("intrinsics")],
            symbols: symbols,
            interner: interner
        )
        let coroutineSuspendedName = interner.intern("COROUTINE_SUSPENDED")
        let hasBundledCoroutineSuspended = BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: intrinsicsPkg,
            name: coroutineSuspendedName,
            arity: 0
        )
        if !hasBundledCoroutineSuspended {
            registerSyntheticCoroutineTopLevelProperty(
                named: "COROUTINE_SUSPENDED",
                packageFQName: intrinsicsPkg,
                returnType: types.nullableAnyType,
                externalLinkName: "kk_coroutine_suspended",
                symbols: symbols,
                interner: interner
            )
        }
    }
}
