/// Array and list conversion call rewrites.
extension CollectionLiteralConstructionLoweringPass {
    func rewriteArrayConversionCall(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        thrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
    // toMutableList() on array → kk_array_toMutableList (STDLIB-087)
    if callee == lookup.toMutableListName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            let toMutableListResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToMutableListName,
                arguments: [receiverID],
                result: toMutableListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.listExprIDs.insert(result.rawValue)
                state.listExprIDs.insert(toMutableListResult.rawValue)
                loweredBody.append(.copy(from: toMutableListResult, to: result))
            }
            return true
        }
    }

    // KSP-628 + KSP-629: the List receivers of toTypedArray /
    // to{Char,Boolean,Short,Double,Float,Int,Long,Byte,UByte,UShort,UInt,ULong}Array
    // are source-backed (ArrayConversions.kt) and lower through normal function resolution.

    // toTypedArray() on array → kk_array_copyOf (STDLIB-087)
    if callee == lookup.toTypedArrayName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            let toArrayResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfName,
                arguments: [receiverID],
                result: toArrayResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                state.arrayExprIDs.insert(result.rawValue)
                state.arrayExprIDs.insert(toArrayResult.rawValue)
                loweredBody.append(.copy(from: toArrayResult, to: result))
            }
            return true
        }
    }

    // copyOf / copyOfRange / fill on array (STDLIB-089)
    if callee == lookup.copyOfName, (1...4).contains(arguments.count) {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            let copyResult = module.arena.appendTemporary(type: nil
            )
            let runtimeCallee: InternedString
            let runtimeArguments: [KIRExprID]
            let runtimeCanThrow: Bool
            if arguments.count == 1 {
                runtimeCallee = lookup.kkArrayCopyOfName
                runtimeArguments = [receiverID]
                runtimeCanThrow = false
            } else if arguments.count == 2 {
                runtimeCallee = lookup.kkArrayCopyOfNewSizeName
                runtimeArguments = arguments
                runtimeCanThrow = false
            } else {
                let closureRawID: KIRExprID
                if arguments.count == 4 {
                    closureRawID = arguments[3]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                runtimeCallee = lookup.kkArrayCopyOfNewSizeInitName
                runtimeArguments = [receiverID, arguments[1], arguments[2], closureRawID]
                runtimeCanThrow = true
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: runtimeArguments,
                result: copyResult,
                canThrow: runtimeCanThrow,
                thrownResult: runtimeCanThrow ? thrownResult : nil
            ))
            if let result {
                state.arrayExprIDs.insert(result.rawValue)
                state.arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.copyOfRangeName, arguments.count == 3 {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            let copyResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfRangeName,
                arguments: arguments,
                result: copyResult,
                canThrow: true,
                thrownResult: thrownResult
            ))
            if let result {
                state.arrayExprIDs.insert(result.rawValue)
                state.arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }
    }

    if callee == lookup.fillName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFillName,
                arguments: arguments,
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
