
extension CollectionLiteralConstructionLoweringPass {

    /// Rewrites late-stage runtime call adapters after direct collection/HOF rewrites.
    func rewriteRuntimeAdapterCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        function: KIRFunction,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // --- sortedWith with Comparator argument (STDLIB-649) ---
        // When kk_list_sortedWith is emitted as a .call (from synthetic stub),
        // the comparator argument needs trampoline/closure expansion.
        // args layout: [receiver, comparatorExpr]
        if callee == lookup.kkListSortedWithName, arguments.count == 2 {
            let receiverID = arguments[0]
            let comparatorExpr = arguments[1]
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkListSortedWithName,
                arguments: [receiverID, comparatorExpr, zeroExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
            }
            return true
        }

        return false
    }
}
