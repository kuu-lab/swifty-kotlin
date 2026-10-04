
extension CollectionVirtualCallRewriteLoweringPass {
    // MARK: - Collection property operations (size, contains, isEmpty)

    func rewriteCollectionPropertyVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        state: CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        if callee == lookup.sizeName || callee == lookup.countName, arguments.isEmpty {
            if state.contains(.list, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.contains(.set, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.contains(.map, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapSizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.contains(.array, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkArraySizeName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.containsName, arguments.count == 1 {
            if state.contains(.set, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetContainsName,
                    arguments: [receiver] + arguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
        }

        if callee == lookup.isEmptyName, arguments.isEmpty {
            if state.contains(.list, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkListIsEmptyName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.contains(.set, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkSetIsEmptyName,
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return true
            }
            if state.contains(.map, receiver) {
                loweredBody.append(.call(
                    symbol: nil,
                    callee: lookup.kkMapIsEmptyName,
                    arguments: [receiver],
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
