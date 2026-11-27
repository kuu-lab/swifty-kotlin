extension CollectionLiteralConstructionLoweringPass {
    struct CollectionCallRewrite {
        let callee: InternedString
        let arguments: [KIRExprID]
        let result: KIRExprID?
        let canThrow: Bool
        let thrownResult: KIRExprID?
    }

    struct CollectionCallRewriteContext {
        let module: KIRModule
        let lookup: CollectionLiteralLookupTables
    }

    struct CollectionCallRewriteResult {
        let instructions: [KIRInstruction]
    }

    func rewriteCollectionHOFCall(
        call: CollectionCallRewrite,
        state: inout CollectionRewriteState,
        ctx: CollectionCallRewriteContext
    ) -> CollectionCallRewriteResult? {
        let lookup = ctx.lookup
        guard isCollectionHOFMemberName(call.callee, lookup: lookup) else {
            return nil
        }

        var instructions: [KIRInstruction] = []

        guard call.arguments.count == 2 || call.arguments.count == 3 else {
            return nil
        }
        let receiverID = call.arguments[0]
        let lambdaID = call.arguments[1]

        if state.listExprIDs.contains(receiverID.rawValue),
           let kkName = lookup.collectionHOFRuntimeName(ownerKind: .list, callee: call.callee, arity: 1)
        {
            let closureRawID = closureRawArgument(for: call.arguments, module: ctx.module, instructions: &instructions)
            let hofResult = ctx.module.arena.appendTemporary(type: nil
            )
            instructions.append(.call(
                callee: kkName,
                arguments: [receiverID, lambdaID, closureRawID],
                result: hofResult,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            ))
            if listHOFReturnsList(call.callee, lookup: lookup) {
                state.tagListResult(call.result, temporary: hofResult)
            }
            if let result = call.result {
                instructions.append(.copy(from: hofResult, to: result))
            }
            return CollectionCallRewriteResult(instructions: instructions)
        }

        return nil
    }

    private func isCollectionHOFMemberName(
        _ callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> Bool {
        callee == lookup.mapName
            || callee == lookup.filterName
            || callee == lookup.forEachName
            || callee == lookup.onEachName
            || callee == lookup.flatMapName
            || callee == lookup.anyName
            || callee == lookup.noneName
            || callee == lookup.allName
            || callee == lookup.mapValuesName
            || callee == lookup.mapKeysName
            || callee == lookup.toListName
    }

    private func closureRawArgument(
        for arguments: [KIRExprID],
        module: KIRModule,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if arguments.count == 3 {
            return arguments[2]
        }
        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        return zeroExpr
    }

    private func listHOFReturnsList(
        _ callee: InternedString,
        lookup: CollectionLiteralLookupTables
    ) -> Bool {
        callee == lookup.mapName
            || callee == lookup.flatMapName
            || callee == lookup.flatMapIndexedName
            || callee == lookup.onEachName
    }
}
