extension CollectionLiteralConstructionLoweringPass {
    func rewriteAccumulationHigherOrderCollectionCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
    if callee == lookup.kkSequenceReduceIndexedName, arguments.count == 2 || arguments.count == 3 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let lambdaID = arguments[1]
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] } else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = lookup.kkSequenceReduceIndexedName
            let callResult = result ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }
    if callee == lookup.kkSequenceReduceIndexedOrNullName,
       arguments.count == 2 || arguments.count == 3 {
        let receiverID = arguments[0]; let lambdaID = arguments[1]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let closureRawID: KIRExprID
            if arguments.count == 3 { closureRawID = arguments[2] } else { let z = module.arena.appendExpr(.intLiteral(0), type: nil); loweredBody.append(.constValue(result: z, value: .intLiteral(0))); closureRawID = z }
            let kkName = lookup.kkSequenceReduceIndexedOrNullName
            let callResult = result ?? module.arena.appendTemporary(type: nil)
            loweredBody.append(.call(callee: kkName, arguments: [receiverID, lambdaID, closureRawID], result: callResult, canThrow: canThrow, thrownResult: thrownResult))
            return true
        }
    }

    return false
    }
}
