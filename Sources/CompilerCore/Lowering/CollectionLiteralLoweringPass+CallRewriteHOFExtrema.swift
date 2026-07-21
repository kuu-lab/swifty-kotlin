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
    if callee == lookup.sumOfName || callee == lookup.sumByName || callee == lookup.sumByDoubleName {
        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString
                if callee == lookup.sumByName {
                    kkName = lookup.kkListSumByName
                } else if callee == lookup.sumByDoubleName {
                    kkName = lookup.kkListSumByDoubleName
                } else {
                    kkName = lookup.kkListSumOfName
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

    if callee == lookup.minName || callee == lookup.maxOrNullName || callee == lookup.minOrNullName {
        if arguments.count == 1 {
            let receiverID = arguments[0]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString = switch callee {
                case lookup.minName: lookup.kkListMinName
                case lookup.maxOrNullName: lookup.kkListMaxOrNullName
                default: lookup.kkListMinOrNullName
                }
                let isThrowingMin = callee == lookup.minName
                let hofResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID],
                    result: hofResult,
                    canThrow: isThrowingMin,
                    thrownResult: isThrowingMin ? thrownResult : nil
                ))
                if let result {
                    loweredBody.append(.copy(from: hofResult, to: result))
                }
                return true
            }
        }
    }
    // maxBy / maxByOrNull / minBy / minByOrNull / maxOfOrNull / minOfOrNull / maxOf / minOf (STDLIB-301)
    if callee == lookup.maxByName || callee == lookup.maxByOrNullName
        || callee == lookup.minByName || callee == lookup.minByOrNullName
        || callee == lookup.maxOfOrNullName || callee == lookup.minOfOrNullName
        || callee == lookup.maxOfName || callee == lookup.minOfName
    {
        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let lambdaID = arguments[1]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let closureRawID: KIRExprID
                if arguments.count == 3 {
                    closureRawID = arguments[2]
                } else {
                    let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawID = zeroExpr
                }
                let kkName: InternedString = switch callee {
                case lookup.maxByName: lookup.kkListMaxByName
                case lookup.maxByOrNullName: lookup.kkListMaxByOrNullName
                case lookup.minByName: lookup.kkListMinByName
                case lookup.minByOrNullName: lookup.kkListMinByOrNullName
                case lookup.maxOfOrNullName: lookup.kkListMaxOfOrNullName
                case lookup.minOfOrNullName: lookup.kkListMinOfOrNullName
                case lookup.maxOfName: lookup.kkListMaxOfName
                default: lookup.kkListMinOfName
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

    // maxWith / maxWithOrNull / minWith / minWithOrNull (comparator-based) (STDLIB-301c)
    if callee == lookup.maxWithName || callee == lookup.maxWithOrNullName
        || callee == lookup.minWithName || callee == lookup.minWithOrNullName
    {
        if arguments.count == 2 || arguments.count == 3 {
            let receiverID = arguments[0]
            let comparatorExpr = arguments[1]
            if state.listExprIDs.contains(receiverID.rawValue) {
                let kkName: InternedString = switch callee {
                case lookup.maxWithName: lookup.kkListMaxWithName
                case lookup.maxWithOrNullName: lookup.kkListMaxWithOrNullName
                case lookup.minWithName: lookup.kkListMinWithName
                default: lookup.kkListMinWithOrNullName
                }
                let source = isComparatorFromCall(
                    exprID: comparatorExpr,
                    body: function.body,
                    multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                    nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                    nullsLastCallee: lookup.kkComparatorNullsLastName,
                    nullsFirstComparableCallee: lookup.kkComparatorNullsFirstComparableName,
                    nullsLastNaturalCallee: lookup.kkComparatorNullsLastNaturalName,
                    multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                    multiSelectorVarargCallee: lookup.kkComparatorFromMultiSelectorsVarargName,
                )
                if let (trampolineName, closureExpr) = retainedComparatorRuntimePair(
                    source: source,
                    comparatorExpr: comparatorExpr,
                    module: module,
                    lookup: lookup,
                    loweredBody: &loweredBody
                ) {
                    let trampolineExpr = module.arena.appendExpr(.externSymbolAddress(trampolineName), type: nil)
                    loweredBody.append(.constValue(result: trampolineExpr, value: .externSymbolAddress(trampolineName)))
                    let hofResult = module.arena.appendTemporary(type: nil
                    )
                    loweredBody.append(.call(
                        symbol: nil,
                        callee: kkName,
                        arguments: [receiverID, trampolineExpr, closureExpr],
                        result: hofResult,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    if let result {
                        loweredBody.append(.copy(from: hofResult, to: result))
                    }
                    return true
                } else {
                    // Direct lambda or source-backed Comparator object.
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
                        arguments: [receiverID, comparatorExpr, closureRawID],
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
    }

    // maxOfWith / maxOfWithOrNull / minOfWith / minOfWithOrNull (comparator + selector) (STDLIB-301d)
    if callee == lookup.maxOfWithName || callee == lookup.maxOfWithOrNullName
        || callee == lookup.minOfWithName || callee == lookup.minOfWithOrNullName
    {
        if arguments.count >= 3 && arguments.count <= 5 {
            let receiverID = arguments[0]
            let cmpExpr = arguments[1]
            let selLambdaID: KIRExprID
            let selClosureRawID: KIRExprID
            if state.listExprIDs.contains(receiverID.rawValue) {
                // Extract selector and its closure from remaining arguments
                if arguments.count == 5 {
                    // [receiver, cmp, cmpClosure, sel, selClosure] — already expanded by VirtualCall path
                    // Still need to inject trampoline for the comparator
                    selLambdaID = arguments[3]
                    selClosureRawID = arguments[4]
                } else if arguments.count == 4 {
                    let thirdExpr = module.arena.expr(arguments[2])
                    let fourthExpr = module.arena.expr(arguments[3])
                    let thirdLooksCallable: Bool = switch thirdExpr {
                    case .symbolRef, .externSymbolAddress:
                        true
                    default:
                        false
                    }
                    let fourthLooksCallable: Bool = switch fourthExpr {
                    case .symbolRef, .externSymbolAddress:
                        true
                    default:
                        false
                    }
                    if !thirdLooksCallable, fourthLooksCallable {
                        selLambdaID = arguments[3]
                        selClosureRawID = {
                            let z = module.arena.appendExpr(.intLiteral(0), type: nil)
                            loweredBody.append(.constValue(result: z, value: .intLiteral(0)))
                            return z
                        }()
                    } else {
                        selLambdaID = arguments[2]
                        selClosureRawID = arguments[3]
                    }
                } else {
                    // arguments.count == 3: [receiver, cmp, sel]
                    selLambdaID = arguments[2]
                    selClosureRawID = {
                        let z = module.arena.appendExpr(.intLiteral(0), type: nil)
                        loweredBody.append(.constValue(result: z, value: .intLiteral(0)))
                        return z
                    }()
                }
                // Inject trampoline for the comparator argument
                let cmpSource = isComparatorFromCall(
                    exprID: cmpExpr,
                    body: function.body,
                    multiSelectorCallee: lookup.kkComparatorFromMultiSelectorsName,
                    nullsFirstCallee: lookup.kkComparatorNullsFirstName,
                    nullsLastCallee: lookup.kkComparatorNullsLastName,
                    nullsFirstComparableCallee: lookup.kkComparatorNullsFirstComparableName,
                    nullsLastNaturalCallee: lookup.kkComparatorNullsLastNaturalName,
                    multiSelector3Callee: lookup.kkComparatorFromMultiSelectors3Name,
                    multiSelectorVarargCallee: lookup.kkComparatorFromMultiSelectorsVarargName,
                )
                let (cmpFunctionExpr, cmpClosureExpr): (KIRExprID, KIRExprID)
                if let (cmpTrampolineName, retainedClosureExpr) = retainedComparatorRuntimePair(
                    source: cmpSource,
                    comparatorExpr: cmpExpr,
                    module: module,
                    lookup: lookup,
                    loweredBody: &loweredBody
                ) {
                    let cmpTrampolineExpr = module.arena.appendExpr(.externSymbolAddress(cmpTrampolineName), type: nil)
                    loweredBody.append(.constValue(
                        result: cmpTrampolineExpr,
                        value: .externSymbolAddress(cmpTrampolineName)
                    ))
                    cmpFunctionExpr = cmpTrampolineExpr
                    cmpClosureExpr = retainedClosureExpr
                } else {
                    let zero = module.arena.appendExpr(.intLiteral(0), type: nil)
                    loweredBody.append(.constValue(result: zero, value: .intLiteral(0)))
                    cmpFunctionExpr = cmpExpr
                    cmpClosureExpr = zero
                }
                let kkName: InternedString = switch callee {
                case lookup.maxOfWithName: lookup.kkListMaxOfWithName
                case lookup.maxOfWithOrNullName: lookup.kkListMaxOfWithOrNullName
                case lookup.minOfWithName: lookup.kkListMinOfWithName
                default: lookup.kkListMinOfWithOrNullName
                }
                let hofResult = module.arena.appendTemporary(type: nil
                )
                loweredBody.append(.call(
                    symbol: nil,
                    callee: kkName,
                    arguments: [receiverID, cmpFunctionExpr, cmpClosureExpr, selLambdaID, selClosureRawID],
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
