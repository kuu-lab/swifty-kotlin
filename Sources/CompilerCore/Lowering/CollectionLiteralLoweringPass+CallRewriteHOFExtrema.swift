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
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
    if callee == lookup.sumByName || callee == lookup.sumByDoubleName {
        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString = if callee == lookup.sumByName {
                    lookup.kkListSumByName
                } else {
                    lookup.kkListSumByDoubleName
                }
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let hofResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID, lambdaID, closureRawID],
                    result: hofResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult
                ))
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }

        return false
    }
}
