/// Numeric and extrema higher-order collection rewrites, including comparator trampoline expansion.
extension CollectionLiteralConstructionLoweringPass {
    func rewriteExtremaHigherOrderCollectionCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        function: KIRFunction,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        return false
    }
}
