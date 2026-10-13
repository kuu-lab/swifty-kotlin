/// Synthetic coroutine package tree and the `RestrictsSuspension`
/// residual: the kotlin/kotlinx package anchors plus the annotation
/// class retained for --no-stdlib compilations.
///
/// Extracted from `registerSyntheticCoroutineStubs`
/// (HeaderHelpers+SyntheticCoroutineRegistry.swift). The extracted
/// methods thread the shared registry state through `context` so the
/// call order and side effects are unchanged.

extension DataFlowSemaPhase {
    func registerCoroutinePackageTree(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let interner = context.interner

        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Build the synthetic package tree explicitly so the coroutine stubs
        // stay stable across incremental rebuilds.
        let kotlinCoroutinesPkg = ensureSyntheticCoroutinePackage(
            kotlinPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutinesIntrinsicsPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("intrinsics")],
            symbols: symbols,
            interner: interner
        )
        let cancellationPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("cancellation")],
            symbols: symbols,
            interner: interner
        )
        let kotlinxPkg = ensureSyntheticCoroutinePackage(
            [interner.intern("kotlinx")],
            symbols: symbols,
            interner: interner
        )
        let coroutinesPkg = ensureSyntheticCoroutinePackage(
            kotlinxPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let kotlinCoroutinesCancellationPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("cancellation")],
            symbols: symbols,
            interner: interner
        )

        context.kotlinPkg = kotlinPkg
        context.kotlinCoroutinesPkg = kotlinCoroutinesPkg
        context.kotlinCoroutinesIntrinsicsPkg = kotlinCoroutinesIntrinsicsPkg
        context.cancellationPkg = cancellationPkg
        context.coroutinesPkg = coroutinesPkg
        context.kotlinCoroutinesCancellationPkg = kotlinCoroutinesCancellationPkg
    }

    func registerRestrictsSuspensionResidual(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg

        let restrictsSuspensionFQName = kotlinCoroutinesPkg + [interner.intern("RestrictsSuspension")]
        // The bundled declaration owns this annotation and its implicit constructor.
        // Retain the residual registration only for --no-stdlib compilations.
        if !bundledIndex.containsNominal(fqName: restrictsSuspensionFQName) {
            let restrictsSuspensionSymbol = ensureAnnotationClassSymbol(
                named: "RestrictsSuspension",
                in: kotlinCoroutinesPkg,
                symbols: symbols,
                interner: interner
            )
            if let kotlinCoroutinesPkgSymbol = symbols.lookup(fqName: kotlinCoroutinesPkg) {
                symbols.setParentSymbol(kotlinCoroutinesPkgSymbol, for: restrictsSuspensionSymbol)
            }
            attachRestrictsSuspensionAnnotationMetadata(
                to: restrictsSuspensionSymbol,
                symbols: symbols
            )
            registerSyntheticConstructorStubs(
                [SyntheticConstructorStubSpec()],
                ownerType: .classType(
                    fqName: ["kotlin", "coroutines", "RestrictsSuspension"],
                    args: [],
                    nullability: .nonNull
                ),
                context: SyntheticStubRegistrationContext(
                    ownerFQName: restrictsSuspensionFQName,
                    parentSymbol: restrictsSuspensionSymbol
                ),
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    func registerChannelAndFlowPackages(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let interner = context.interner
        let coroutinesPkg = context.coroutinesPkg

        let channelsPkg = ensureSyntheticCoroutinePackage(
            coroutinesPkg + [interner.intern("channels")],
            symbols: symbols,
            interner: interner
        )
        let flowPkg = ensureSyntheticCoroutinePackage(
            coroutinesPkg + [interner.intern("flow")],
            symbols: symbols,
            interner: interner
        )

        context.channelsPkg = channelsPkg
        context.flowPkg = flowPkg
    }
}
