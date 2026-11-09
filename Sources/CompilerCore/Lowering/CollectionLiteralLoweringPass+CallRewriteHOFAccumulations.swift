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
    // reduceIndexed: args = [receiver, lambda, closureRaw?]
    // KSP-1355: source-bound Sequence.reduceIndexed calls compile the bundled
    // body; this arm only normalizes residual calls that were already lowered
    // to the kk_sequence_reduceIndexed entry point (unresolved receivers).
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
    // reduceIndexedOrNull: args = [receiver, lambda, closureRaw?]
    // KSP-1355: source-bound Sequence.reduceIndexedOrNull calls compile the
    // bundled body; this arm only normalizes residual calls that were already
    // lowered to the kk_sequence_reduceIndexedOrNull entry point.
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
