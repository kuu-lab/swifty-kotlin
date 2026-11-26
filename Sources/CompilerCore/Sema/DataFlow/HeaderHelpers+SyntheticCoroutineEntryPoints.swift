extension DataFlowSemaPhase {
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
                returnType: types.anyType,
                externalLinkName: "kk_coroutine_suspended",
                symbols: symbols,
                interner: interner
            )
        }
    }
}
