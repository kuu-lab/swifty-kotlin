
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
        // Rewrite println on list/map → kk_list_to_string / kk_map_to_string
        if callee == lookup.kkPrintlnAnyName || callee == lookup.printlnName, arguments.count == 1 {
            let argID = arguments[0]
            if state.listExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.setExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapExprIDs.contains(argID.rawValue) {
                let strResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapToStringName,
                    arguments: [argID],
                    result: strResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkPrintlnAnyName,
                    arguments: [strResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.kkAnyToStringName, arguments.count >= 1 {
            let argID = arguments[0]
            if state.listExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.setExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.mapExprIDs.contains(argID.rawValue) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapToStringName,
                    arguments: [argID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        return false
    }
}
