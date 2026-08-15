import Foundation

/// Virtual-call rewrite for `Array`-typed receivers
/// (STDLIB-087/088/089).
///
/// Split out from `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`.
extension CollectionVirtualCallRewriteLoweringPass {
    // MARK: - Array virtual call operations (STDLIB-087/088/089)

    func rewriteArrayVirtualCall(
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        // Non-tracked array receivers are now classified by static type via
        // classifyReceiverByStaticType (LOWERING-001) before reaching here.
        guard arrayExprIDs.contains(receiver.rawValue) else { return false }

        // toList on array → kk_array_toList (result is List)
        if callee == lookup.toListName, arguments.isEmpty {
            let toListResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToListName,
                arguments: [receiver],
                result: toListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(toListResult.rawValue)
                loweredBody.append(.copy(from: toListResult, to: result))
            }
            return true
        }

        // toMutableList on array → kk_array_toMutableList (result is MutableList)
        if callee == lookup.toMutableListName, arguments.isEmpty {
            let toMutableListResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayToMutableListName,
                arguments: [receiver],
                result: toMutableListResult,
                canThrow: false,
                thrownResult: nil
            ))
            if let result {
                listExprIDs.insert(result.rawValue)
                listExprIDs.insert(toMutableListResult.rawValue)
                loweredBody.append(.copy(from: toMutableListResult, to: result))
            }
            return true
        }

        // copyOf on array → kk_array_copyOf* (result is Array)
        if callee == lookup.copyOfName, arguments.isEmpty || arguments.count == 1 || arguments.count == 2 || arguments.count == 3 {
            let copyResult = module.arena.appendTemporary(type: nil
            )
            let runtimeCallee: InternedString
            let runtimeArguments: [KIRExprID]
            let canThrow: Bool
            if arguments.isEmpty {
                runtimeCallee = lookup.kkArrayCopyOfName
                runtimeArguments = [receiver]
                canThrow = false
            } else if arguments.count == 1 {
                runtimeCallee = lookup.kkArrayCopyOfNewSizeName
                runtimeArguments = [receiver] + arguments
                canThrow = false
            } else {
                let closureRawExpr: KIRExprID
                if arguments.count == 3 {
                    closureRawExpr = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawExpr = zeroExpr
                }
                runtimeCallee = lookup.kkArrayCopyOfNewSizeInitName
                runtimeArguments = [receiver, arguments[0], arguments[1], closureRawExpr]
                canThrow = true
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: runtimeArguments,
                result: copyResult,
                canThrow: canThrow,
                thrownResult: canThrow ? origThrownResult : nil
            ))
            if let result {
                arrayExprIDs.insert(result.rawValue)
                arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }

        // copyOfRange on array → kk_array_copyOfRange (result is Array)
        if callee == lookup.copyOfRangeName, arguments.count == 2 {
            let copyResult = module.arena.appendTemporary(type: nil
            )
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayCopyOfRangeName,
                arguments: [receiver] + arguments,
                result: copyResult,
                canThrow: true,
                thrownResult: origThrownResult
            ))
            if let result {
                arrayExprIDs.insert(result.rawValue)
                arrayExprIDs.insert(copyResult.rawValue)
                loweredBody.append(.copy(from: copyResult, to: result))
            }
            return true
        }

        // fill on array → kk_array_fill
        if callee == lookup.fillName, arguments.count == 1 {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayFillName,
                arguments: [receiver] + arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        // asSequence on array → kk_array_asSequence (STDLIB-471)
        if callee == lookup.asSequenceName, arguments.isEmpty {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkArrayAsSequenceName,
                arguments: [receiver],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        return false
    }
}
