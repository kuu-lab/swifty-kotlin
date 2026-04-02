import Foundation

enum RuntimeFlowTag: Int64 {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
    case onEach = 4
    case distinctUntilChanged = 5
    case transform = 6
    case takeWhile = 7
    case dropWhile = 8
    case buffer = 9
    case conflate = 10
    case flowOn = 11
    case debounce = 12
    case sample = 13
    case delayEach = 14
}

struct FlowLoweringNames {
    let flow: InternedString
    let emit: InternedString
    let collect: InternedString
    let map: InternedString
    let filter: InternedString
    let take: InternedString
    let transform: InternedString
    let takeWhile: InternedString
    let dropWhile: InternedString
    let flatMapConcat: InternedString
    let flatMapMerge: InternedString
    let flatMapLatest: InternedString
    let combine: InternedString
    let zip: InternedString
    let merge: InternedString
    let buffer: InternedString
    let conflate: InternedString
    let flowOn: InternedString
    let debounce: InternedString
    let sample: InternedString
    let delayEach: InternedString
    let toList: InternedString
    let first: InternedString
    let kkFlowCreate: InternedString
    let kkFlowEmit: InternedString
    let kkFlowCollect: InternedString
    let kkFlowRetain: InternedString
    let kkFlowRelease: InternedString
    let kkFlowToList: InternedString
    let kkFlowFirst: InternedString
    let kkFlowZip: InternedString
    let kkFlowCombine: InternedString
    let kkFlowMerge: InternedString
    let kkFlowFlatMapConcat: InternedString
    let kkFlowFlatMapMerge: InternedString
    let kkFlowFlatMapLatest: InternedString
}

extension CoroutineLoweringPass {
    /// Lower `flow { }`, `emit`, `map`, `filter`, `take`, `collect` calls to their
    /// runtime ABI equivalents. Mirrors the `sequenceExprIDs` pattern in
    /// `CollectionLiteralLoweringPass`.
    func lowerFlowExpressions(module: KIRModule, ctx: KIRContext) {
        let flowName = ctx.interner.intern("flow")
        let emitName = ctx.interner.intern("emit")
        let collectName = ctx.interner.intern("collect")
        let mapName = ctx.interner.intern("map")
        let filterName = ctx.interner.intern("filter")
        let takeName = ctx.interner.intern("take")
        let transformName = ctx.interner.intern("transform")
        let takeWhileName = ctx.interner.intern("takeWhile")
        let dropWhileName = ctx.interner.intern("dropWhile")
        let flatMapConcatName = ctx.interner.intern("flatMapConcat")
        let flatMapMergeName = ctx.interner.intern("flatMapMerge")
        let flatMapLatestName = ctx.interner.intern("flatMapLatest")
        let combineName = ctx.interner.intern("combine")
        let zipName = ctx.interner.intern("zip")
        let mergeName = ctx.interner.intern("merge")
        let bufferName = ctx.interner.intern("buffer")
        let conflateName = ctx.interner.intern("conflate")
        let flowOnName = ctx.interner.intern("flowOn")
        let debounceName = ctx.interner.intern("debounce")
        let sampleName = ctx.interner.intern("sample")
        let delayEachName = ctx.interner.intern("delayEach")
        let toListName = ctx.interner.intern("toList")
        let firstName = ctx.interner.intern("first")

        let kkFlowCreateName = ctx.interner.intern("kk_flow_create")
        let kkFlowEmitName = ctx.interner.intern("kk_flow_emit")
        let kkFlowCollectName = ctx.interner.intern("kk_flow_collect")
        let kkFlowRetainName = ctx.interner.intern("kk_flow_retain")
        let kkFlowReleaseName = ctx.interner.intern("kk_flow_release")
        let kkFlowToListName = ctx.interner.intern("kk_flow_to_list")
        let kkFlowFirstName = ctx.interner.intern("kk_flow_first")
        let kkFlowZipName = ctx.interner.intern("kk_flow_zip")
        let kkFlowCombineName = ctx.interner.intern("kk_flow_combine")
        let kkFlowMergeName = ctx.interner.intern("kk_flow_merge")
        let kkFlowFlatMapConcatName = ctx.interner.intern("kk_flow_flat_map_concat")
        let kkFlowFlatMapMergeName = ctx.interner.intern("kk_flow_flat_map_merge")
        let kkFlowFlatMapLatestName = ctx.interner.intern("kk_flow_flat_map_latest")

        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated: KIRFunction = function

            var flowExprIDs: Set<Int32> = []
            var flowGlobalSymbols: Set<SymbolID> = []

            func markFlowExpr(_ result: KIRExprID?) -> Bool {
                guard let result else { return false }
                return flowExprIDs.insert(result.rawValue).inserted
            }

            var symbolByExprRaw: [Int32: SymbolID] = [:]
            var propagatedSymbols = true
            while propagatedSymbols {
                propagatedSymbols = false
                for instruction in function.body {
                    switch instruction {
                    case let .constValue(result, .symbolRef(symbol)):
                        if symbolByExprRaw[result.rawValue] != symbol {
                            symbolByExprRaw[result.rawValue] = symbol
                            propagatedSymbols = true
                        }
                    case let .copy(from, to):
                        if let symbol = symbolByExprRaw[from.rawValue],
                           symbolByExprRaw[to.rawValue] != symbol
                        {
                            symbolByExprRaw[to.rawValue] = symbol
                            propagatedSymbols = true
                        }
                    default:
                        continue
                    }
                }
            }

            func isSymbolBackedFlowExpr(_ exprID: KIRExprID) -> Bool {
                if let expr = module.arena.expr(exprID), case .symbolRef = expr {
                    return true
                }
                return symbolByExprRaw[exprID.rawValue] != nil
            }

            func isFlowTransformEmitCall(_ callee: InternedString, _ arguments: [KIRExprID]) -> Bool {
                guard callee == kkFlowEmitName, arguments.count == 3 else {
                    return false
                }
                guard let tagExpr = module.arena.expr(arguments[2]),
                      case let .intLiteral(tagValue) = tagExpr,
                      tagValue == RuntimeFlowTag.map.rawValue ||
                      tagValue == RuntimeFlowTag.filter.rawValue ||
                      tagValue == RuntimeFlowTag.take.rawValue
                else {
                    return false
                }
                return true
            }

            var changed = true
            while changed {
                changed = false

                for instruction in function.body {
                    switch instruction {
                    case let .call(symbol, callee, arguments, result, _, _, _, _):
                        if callee == flowName, arguments.count == 1, symbol == nil {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == kkFlowCreateName, arguments.count == 2 {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowTransformEmitCall(callee, arguments) {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == mapName || callee == filterName || callee == takeName,
                           arguments.count == 2 || ((callee == mapName || callee == filterName) && arguments.count == 3),
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if [transformName, takeWhileName, dropWhileName, flatMapConcatName, flatMapMergeName, flatMapLatestName, bufferName, flowOnName, debounceName, sampleName, delayEachName].contains(callee),
                           arguments.count >= 2,
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == conflateName,
                           arguments.count == 1,
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if [combineName, zipName, mergeName].contains(callee) {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == collectName || callee == kkFlowCollectName,
                           arguments.count == 2 || arguments.count == 3,
                           let flowHandleArg = arguments.first
                        {
                            if flowExprIDs.insert(flowHandleArg.rawValue).inserted {
                                changed = true
                            }
                            continue
                        }
                        if callee == emitName,
                           arguments.count == 1,
                           symbol == nil
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }

                    case let .virtualCall(_, callee, receiver, arguments, result, _, _, _):
                        if callee == mapName || callee == filterName || callee == takeName,
                           arguments.count == 1,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if [transformName, takeWhileName, dropWhileName, flatMapConcatName, flatMapMergeName, flatMapLatestName, bufferName, flowOnName, debounceName, sampleName, delayEachName].contains(callee),
                           arguments.count == 1,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == conflateName,
                           arguments.isEmpty,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if callee == collectName,
                           arguments.count == 1,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }

                    case let .copy(from, to):
                        if flowExprIDs.contains(from.rawValue),
                           flowExprIDs.insert(to.rawValue).inserted
                        {
                            changed = true
                        }

                    case let .storeGlobal(value, symbol):
                        if flowExprIDs.contains(value.rawValue) {
                            if flowGlobalSymbols.insert(symbol).inserted {
                                changed = true
                            }
                        } else if flowGlobalSymbols.remove(symbol) != nil {
                            changed = true
                        }

                    case let .loadGlobal(result, symbol):
                        if flowGlobalSymbols.contains(symbol),
                           flowExprIDs.insert(result.rawValue).inserted
                        {
                            changed = true
                        }

                    default:
                        break
                    }
                }
            }

            let hasFlowLikeCalls = function.body.contains { instruction in
                switch instruction {
                case let .call(_, callee, _, _, _, _, _, _):
                        callee == flowName || callee == emitName || callee == collectName ||
                            callee == mapName || callee == filterName || callee == takeName ||
                            callee == transformName || callee == takeWhileName || callee == dropWhileName ||
                            callee == flatMapConcatName || callee == flatMapMergeName || callee == flatMapLatestName ||
                            callee == combineName || callee == zipName || callee == mergeName ||
                            callee == bufferName || callee == conflateName || callee == flowOnName ||
                            callee == debounceName || callee == sampleName || callee == delayEachName ||
                            callee == toListName || callee == firstName ||
                            callee == kkFlowCreateName || callee == kkFlowEmitName || callee == kkFlowCollectName ||
                            callee == kkFlowToListName || callee == kkFlowFirstName
                case let .virtualCall(_, callee, _, _, _, _, _, _):
                    callee == mapName || callee == filterName || callee == takeName || callee == collectName ||
                        callee == transformName || callee == takeWhileName || callee == dropWhileName ||
                        callee == flatMapConcatName || callee == flatMapMergeName || callee == flatMapLatestName ||
                        callee == bufferName || callee == conflateName || callee == flowOnName ||
                        callee == debounceName || callee == sampleName || callee == delayEachName ||
                        callee == toListName || callee == firstName
                default:
                    false
                }
            }

            guard !flowExprIDs.isEmpty || hasFlowLikeCalls else {
                return updated
            }

            var remainingConsumes: [Int32: Int] = [:]
            func markConsume(_ source: KIRExprID) {
                guard flowExprIDs.contains(source.rawValue) else {
                    return
                }
                remainingConsumes[source.rawValue, default: 0] += 1
            }
            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, arguments, _, _, _, _, _):
                    if callee == mapName || callee == filterName || callee == takeName,
                       arguments.count == 2 || ((callee == mapName || callee == filterName) && arguments.count == 3)
                    {
                        markConsume(arguments[0])
                        continue
                    }
                    if callee == collectName || callee == kkFlowCollectName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        markConsume(arguments[0])
                        continue
                    }
                    if (callee == toListName || callee == firstName ||
                        callee == kkFlowToListName || callee == kkFlowFirstName), !arguments.isEmpty {
                        markConsume(arguments[0])
                        continue
                    }
                    if isFlowTransformEmitCall(callee, arguments), arguments.count == 3 {
                        markConsume(arguments[0])
                    }
                case let .virtualCall(_, callee, receiver, arguments, _, _, _, _):
                    if callee == mapName || callee == filterName || callee == takeName || callee == collectName,
                       arguments.count == 1
                    {
                        markConsume(receiver)
                    }
                    if (callee == toListName || callee == firstName), arguments.isEmpty {
                        markConsume(receiver)
                    }
                default:
                    continue
                }
            }

            // Phase 2: rewrite flow instructions.
            let names = FlowLoweringNames(
                flow: flowName,
                emit: emitName,
                collect: collectName,
                map: mapName,
                filter: filterName,
                take: takeName,
                transform: transformName,
                takeWhile: takeWhileName,
                dropWhile: dropWhileName,
                flatMapConcat: flatMapConcatName,
                flatMapMerge: flatMapMergeName,
                flatMapLatest: flatMapLatestName,
                combine: combineName,
                zip: zipName,
                merge: mergeName,
                buffer: bufferName,
                conflate: conflateName,
                flowOn: flowOnName,
                debounce: debounceName,
                sample: sampleName,
                delayEach: delayEachName,
                toList: toListName,
                first: firstName,
                kkFlowCreate: kkFlowCreateName,
                kkFlowEmit: kkFlowEmitName,
                kkFlowCollect: kkFlowCollectName,
                kkFlowRetain: kkFlowRetainName,
                kkFlowRelease: kkFlowReleaseName,
                kkFlowToList: kkFlowToListName,
                kkFlowFirst: kkFlowFirstName,
                kkFlowZip: kkFlowZipName,
                kkFlowCombine: kkFlowCombineName,
                kkFlowMerge: kkFlowMergeName,
                kkFlowFlatMapConcat: kkFlowFlatMapConcatName,
                kkFlowFlatMapMerge: kkFlowFlatMapMergeName,
                kkFlowFlatMapLatest: kkFlowFlatMapLatestName
            )
            let loweredBody = rewriteFlowInstructions(
                originalBody: function.body,
                module: module,
                ctx: ctx,
                flowExprIDs: &flowExprIDs,
                remainingConsumes: &remainingConsumes,
                symbolByExprRaw: symbolByExprRaw,
                names: names
            )

            updated.replaceBody(loweredBody)
            return updated
        }
        module.arena.transformFunctions(transformFunction)
    }
}
