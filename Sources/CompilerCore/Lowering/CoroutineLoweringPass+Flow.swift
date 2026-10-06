
enum RuntimeFlowTag: Int64 {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
    case onEach = 4
    case distinctUntilChanged = 5
    case catchHandler = 6
    case retry = 7
    case retryWhen = 8
    // KUU-1351: tags 9/10 (onErrorReturn/onErrorResume) and 19 (delayEach)
    // backed Flow operators that do not exist in kotlinx-coroutines; the
    // values stay retired so no lowering emits them.
    case transform = 11
    case takeWhile = 12
    case dropWhile = 13
    case buffer = 14
    case conflate = 15
    case flowOn = 16
    case debounce = 17
    case sample = 18
}

struct FlowLoweringNames {
    let flow: InternedString
    let emit: InternedString
    let collect: InternedString
    let collectLatest: InternedString
    let map: InternedString
    let filter: InternedString
    let take: InternedString
    let transform: InternedString
    let single: InternedString
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
    let catchHandler: InternedString
    let retry: InternedString
    let retryWhen: InternedString
    let toList: InternedString
    let first: InternedString
    let kkFlowCreate: InternedString
    let kkFlowEmit: InternedString
    let kkFlowCollect: InternedString
    let kkFlowCollectLatest: InternedString
    let kkFlowRetain: InternedString
    let kkFlowRelease: InternedString
    let kkFlowToList: InternedString
    let kkFlowFirst: InternedString
    let kkFlowSingle: InternedString
    let kkFlowZip: InternedString
    let kkFlowCombine: InternedString
    let kkFlowMerge: InternedString
    let kkFlowFlatMapConcat: InternedString
    let kkFlowFlatMapMerge: InternedString
    let kkFlowFlatMapLatest: InternedString
}

extension CoroutineLoweringPass {
    /// Returns true when `symbol` resolves to a real Kotlin declaration.
    /// Bundled Kotlin declarations imported from a stdlib artifact carry both
    /// `importedLibrary` and `synthetic`, so provenance is checked together
    /// with the compiler-generated `kk_fn_` link name. Runtime bridge stubs
    /// remain intrinsics even when they are source-backed metadata records.
    func hasRealDeclaration(_ symbol: SymbolID?, in ctx: KIRContext) -> Bool {
        guard let symbol, let sema = ctx.sema, let resolvedSymbol = sema.symbols.symbol(symbol) else {
            return false
        }
        if !resolvedSymbol.flags.contains(.synthetic) {
            return true
        }
        return sema.symbols.isSourceBackedSymbol(symbol)
            && CallLowerer.isSourceBackedLinkName(sema.symbols.externalLinkName(for: symbol))
    }

    /// Lower `flow { }`, `emit`, `map`, `filter`, `take`, `collect` calls to their
    /// runtime ABI equivalents. Mirrors the `sequenceExprIDs` pattern in
    /// `CollectionLiteralLoweringPass`.
    func lowerFlowExpressions(module: KIRModule, ctx: KIRContext) {
        let flowName = ctx.interner.intern("flow")
        let emitName = ctx.interner.intern("emit")
        let collectName = ctx.interner.intern("collect")
        let collectLatestName = ctx.interner.intern("collectLatest")
        let mapName = ctx.interner.intern("map")
        let filterName = ctx.interner.intern("filter")
        let takeName = ctx.interner.intern("take")
        let transformName = ctx.interner.intern("transform")
        let singleName = ctx.interner.intern("single")
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
        let catchName = ctx.interner.intern("catch")
        let retryName = ctx.interner.intern("retry")
        let retryWhenName = ctx.interner.intern("retryWhen")
        let toListName = ctx.interner.intern("toList")
        let firstName = ctx.interner.intern("first")

        let kkFlowCreateName = ctx.interner.intern("kk_flow_create")
        let kkFlowEmitName = ctx.interner.intern("kk_flow_emit")
        let kkFlowCollectName = ctx.interner.intern("kk_flow_collect")
        let kkFlowCollectLatestName = ctx.interner.intern("__kk_flow_collectLatest")
        let kkFlowRetainName = ctx.interner.intern("__kk_flow_retain")
        let kkFlowReleaseName = ctx.interner.intern("__kk_flow_release")
        let kkFlowToListName = ctx.interner.intern("__kk_flow_to_list")
        let kkFlowFirstName = ctx.interner.intern("__kk_flow_first")
        let kkFlowSingleName = ctx.interner.intern("__kk_flow_single")
        let kkFlowZipName = ctx.interner.intern("__kk_flow_zip")
        let kkFlowCombineName = ctx.interner.intern("__kk_flow_combine")
        let kkFlowMergeName = ctx.interner.intern("__kk_flow_merge")
        let kkFlowFlatMapConcatName = ctx.interner.intern("__kk_flow_flat_map_concat")
        let kkFlowFlatMapMergeName = ctx.interner.intern("__kk_flow_flat_map_merge")
        let kkFlowFlatMapLatestName = ctx.interner.intern("__kk_flow_flat_map_latest")
        let kkChannelFlowCreateName = ctx.interner.intern("kk_channel_flow_create")
        let kkCallbackFlowCreateName = ctx.interner.intern("kk_callback_flow_create")

        // Fallback for call results whose Sema-inferred type is Flow<T> even
        // though the callee isn't a recognized builder name (e.g. a user
        // function declared `fun f(): Flow<Int>`). Without this, such calls
        // never enter flowExprIDs and downstream `.collect`/`.buffer`/etc.
        // calls on them are left un-lowered, causing a link error.
        let flowClassSymbol = ctx.sema?.symbols.lookup(fqName: [
            ctx.interner.intern("kotlinx"), ctx.interner.intern("coroutines"),
            ctx.interner.intern("flow"), ctx.interner.intern("Flow"),
        ])
        func isFlowClassResultType(_ exprID: KIRExprID) -> Bool {
            guard let flowClassSymbol,
                  let sema = ctx.sema,
                  let type = module.arena.exprType(exprID),
                  case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type))
            else {
                return false
            }
            return classType.classSymbol == flowClassSymbol
        }

        // KUU-963: a bare `emit(x)` call is the Flow builder effect only when
        // it appears inside a `flow { }` builder's scope. Determine that
        // scope module-wide — the lambda passed to `flow`/`kk_flow_create`,
        // plus functions referenced from inside such functions (e.g. a
        // nested `collect { emit(it) }` callback) — so receivers that happen
        // to declare their own `emit` member keep normal dispatch.
        var functionNameBySymbol: [SymbolID: InternedString] = [:]
        var functionSymbolsByName: [InternedString: [SymbolID]] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            functionNameBySymbol[function.symbol] = function.name
            functionSymbolsByName[function.name, default: []].append(function.symbol)
        }
        var flowScopeFunctionSymbols: Set<SymbolID> = []
        var flowScopeFunctionNames: Set<InternedString> = []
        func addFlowScopeSymbol(_ symbol: SymbolID) {
            flowScopeFunctionSymbols.insert(symbol)
            if let name = functionNameBySymbol[symbol] {
                flowScopeFunctionNames.insert(name)
            }
        }
        // Symbols that directly reference a module-declared function from an
        // instruction: `constValue(.symbolRef)` values plus the `symbol` field
        // of direct calls (used by `kk_function_value_adapter_*` forwarders).
        // Suspend machinery calls lowered copies through `$kk_coro_synthetic_*`
        // Sema symbols the arena cannot resolve, so the callee name is also
        // mapped back onto module declarations.
        func referencedFunctionSymbols(
            in instruction: KIRInstruction,
            symbolByExprRaw: [Int32: SymbolID]
        ) -> [SymbolID] {
            var symbols: [SymbolID] = []
            switch instruction {
            case let .constValue(_, .symbolRef(symbol)):
                symbols.append(symbol)
            case let .call(symbol, callee, arguments, _, _, _, _, _),
                 let .virtualCall(symbol, callee, _, arguments, _, _, _, _):
                if let symbol {
                    symbols.append(symbol)
                }
                if let byName = functionSymbolsByName[callee] {
                    symbols.append(contentsOf: byName)
                }
                for argument in arguments {
                    if let symbol = symbolByExprRaw[argument.rawValue] {
                        symbols.append(symbol)
                    }
                }
            default:
                break
            }
            return symbols
        }
        // Calls whose function-value arguments execute with a Flow collector
        // in scope: `flow { }` builders and the Flow operators whose callback
        // may invoke the bare `emit` effect (`transform`, `catch`,
        // `retryWhen`, `onEach`, `onEmpty`, ...). Other argument shapes
        // (ints, handles) simply resolve to no function symbol.
        let flowEmitScopeCalleeNames: Set<InternedString> = [
            flowName, collectName, collectLatestName, mapName, filterName,
            takeName, transformName, takeWhileName, dropWhileName,
            flatMapConcatName, flatMapMergeName, flatMapLatestName,
            combineName, zipName, mergeName, bufferName, conflateName,
            flowOnName, debounceName, sampleName,
            catchName, retryName, retryWhenName,
            ctx.interner.intern("onEach"),
            ctx.interner.intern("onEmpty"),
            kkFlowCreateName, kkChannelFlowCreateName, kkCallbackFlowCreateName,
            // Already-lowered bridge calls carry the callback as a payload:
            // tagged `kk_flow_emit` (transform/map/catch/...), collector
            // references of `kk_flow_collect`, and the flatMap/combine family.
            kkFlowEmitName, kkFlowCollectName, kkFlowCollectLatestName,
            kkFlowFlatMapConcatName, kkFlowFlatMapMergeName, kkFlowFlatMapLatestName,
            kkFlowZipName, kkFlowCombineName, kkFlowMergeName,
        ]
        // Container writes that carry a callback into an object or
        // continuation feeding a flow call: `kk_array_set(obj, i, v)` and
        // `kk_coroutine_launcher_arg_set(cont, i, v)`. kklib-imported call
        // shapes route `flow`/`collect` arguments through these slots
        // (e.g. `.map { }` lowering where the lambda is packed into the
        // collector object next to `externSymbolAddress` launcher thunks).
        let containerWriteCallees: Set<InternedString> = [
            ctx.interner.intern("kk_array_set"),
            ctx.interner.intern("kk_coroutine_launcher_arg_set"),
        ]
        func inputExprs(of instruction: KIRInstruction) -> [KIRExprID] {
            switch instruction {
            case let .call(_, _, arguments, _, _, _, _, _):
                return arguments
            case let .virtualCall(_, _, receiver, arguments, _, _, _, _):
                return [receiver] + arguments
            case let .copy(from, _):
                return [from]
            case let .binary(_, lhs, rhs, _):
                return [lhs, rhs]
            case let .unary(_, operand, _), let .nullAssert(operand, _):
                return [operand]
            case let .jumpIfEqual(lhs, rhs, _):
                return [lhs, rhs]
            case let .jumpIfNotNull(value, _), let .rethrow(value),
                 let .returnValue(value), let .storeGlobal(value, _):
                return [value]
            case let .nonLocalReturn(value, _):
                return value.map { [$0] } ?? []
            default:
                return []
            }
        }
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            var symbolByExprRaw: [Int32: SymbolID] = [:]
            for instruction in function.body {
                if case let .constValue(result, .symbolRef(symbol)) = instruction {
                    symbolByExprRaw[result.rawValue] = symbol
                }
            }
            var propagatedSeedSymbols = true
            while propagatedSeedSymbols {
                propagatedSeedSymbols = false
                for instruction in function.body {
                    if case let .copy(from, to) = instruction,
                       let symbol = symbolByExprRaw[from.rawValue],
                       symbolByExprRaw[to.rawValue] == nil
                    {
                        symbolByExprRaw[to.rawValue] = symbol
                        propagatedSeedSymbols = true
                    }
                }
            }
            var producerByResultRaw: [Int32: KIRInstruction] = [:]
            var writtenValuesByTargetRaw: [Int32: [KIRExprID]] = [:]
            for instruction in function.body {
                switch instruction {
                case let .copy(from, to):
                    writtenValuesByTargetRaw[to.rawValue, default: []].append(from)
                case let .call(_, callee, arguments, result, _, _, _, _):
                    if let result {
                        producerByResultRaw[result.rawValue] = instruction
                    }
                    if arguments.count == 3, containerWriteCallees.contains(callee) {
                        writtenValuesByTargetRaw[arguments[0].rawValue, default: []]
                            .append(arguments[2])
                    }
                case let .virtualCall(_, _, _, _, result, _, _, _):
                    if let result {
                        producerByResultRaw[result.rawValue] = instruction
                    }
                default:
                    break
                }
            }
            // Bounded closure from a flow-call argument to every expression
            // that produced it or was written into the containers carrying it,
            // so indirect callback shapes still resolve to a lambda symbol.
            func seedFlowArgumentClosure(_ root: KIRExprID) {
                var queue: [KIRExprID] = [root]
                var seen: Set<Int32> = []
                while let expr = queue.popLast() {
                    guard seen.insert(expr.rawValue).inserted else {
                        continue
                    }
                    if let symbol = symbolByExprRaw[expr.rawValue] {
                        addFlowScopeSymbol(symbol)
                    }
                    if let producer = producerByResultRaw[expr.rawValue] {
                        queue.append(contentsOf: inputExprs(of: producer))
                    }
                    if let writes = writtenValuesByTargetRaw[expr.rawValue] {
                        queue.append(contentsOf: writes)
                    }
                }
            }
            for instruction in function.body {
                let seedArguments: [KIRExprID]?
                switch instruction {
                case let .call(_, callee, arguments, _, _, _, _, _):
                    seedArguments = flowEmitScopeCalleeNames.contains(callee) ? arguments : nil
                case let .virtualCall(_, callee, _, arguments, _, _, _, _):
                    seedArguments = flowEmitScopeCalleeNames.contains(callee) ? arguments : nil
                default:
                    seedArguments = nil
                }
                guard let arguments = seedArguments
                else {
                    continue
                }
                for lambdaArg in arguments {
                    seedFlowArgumentClosure(lambdaArg)
                    // Convention-based fallback for synthetic lambda names,
                    // mirroring FlowLoweringPass.
                    flowScopeFunctionNames.insert(
                        ctx.interner.intern("kk_lambda_\(lambdaArg.rawValue)")
                    )
                }
            }
        }
        func isFlowScopeFunction(_ function: KIRFunction) -> Bool {
            flowScopeFunctionSymbols.contains(function.symbol)
                || flowScopeFunctionNames.contains(function.name)
        }
        // Worklist BFS: scan each in-scope function once; newly discovered
        // functions are queued for their own scan.
        var flowScopeWorklist: [SymbolID] = []
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  isFlowScopeFunction(function)
            else {
                continue
            }
            flowScopeWorklist.append(function.symbol)
        }
        while let scopeSymbol = flowScopeWorklist.popLast() {
            guard let function = module.arena.function(for: scopeSymbol) else {
                continue
            }
            var symbolByExprRaw: [Int32: SymbolID] = [:]
            for instruction in function.body {
                if case let .constValue(result, .symbolRef(symbol)) = instruction {
                    symbolByExprRaw[result.rawValue] = symbol
                }
            }
            for instruction in function.body {
                for symbol in referencedFunctionSymbols(in: instruction, symbolByExprRaw: symbolByExprRaw)
                where functionNameBySymbol[symbol] != nil
                    && flowScopeFunctionSymbols.insert(symbol).inserted {
                    if let name = functionNameBySymbol[symbol] {
                        flowScopeFunctionNames.insert(name)
                    }
                    flowScopeWorklist.append(symbol)
                }
            }
        }
        let freshFunctions = freshFlowFunctions(module: module, ctx: ctx)
        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated: KIRFunction = function

            var flowExprIDs: Set<Int32> = []
            var flowGlobalSymbols: Set<SymbolID> = []

            func markFlowExpr(_ result: KIRExprID?) -> Bool {
                guard let result else { return false }
                return flowExprIDs.insert(result.rawValue).inserted
            }

            var symbolByExprRaw: [Int32: SymbolID] = [:]
            var ambiguousSymbolExprRaws: Set<Int32> = []

            func markAmbiguousSymbolExpr(_ raw: Int32) -> Bool {
                var changed = false
                if symbolByExprRaw.removeValue(forKey: raw) != nil {
                    changed = true
                }
                if ambiguousSymbolExprRaws.insert(raw).inserted {
                    changed = true
                }
                return changed
            }

            for instruction in function.body {
                guard case let .constValue(result, .symbolRef(symbol)) = instruction else {
                    continue
                }
                let raw = result.rawValue
                if let existing = symbolByExprRaw[raw], existing != symbol {
                    _ = markAmbiguousSymbolExpr(raw)
                } else if !ambiguousSymbolExprRaws.contains(raw) {
                    symbolByExprRaw[raw] = symbol
                }
            }

            var propagatedSymbols = true
            while propagatedSymbols {
                propagatedSymbols = false
                for instruction in function.body {
                    guard case let .copy(from, to) = instruction else {
                        continue
                    }

                    let fromRaw = from.rawValue
                    let toRaw = to.rawValue
                    if ambiguousSymbolExprRaws.contains(fromRaw) {
                        if markAmbiguousSymbolExpr(toRaw) {
                            propagatedSymbols = true
                        }
                        continue
                    }
                    guard let symbol = symbolByExprRaw[fromRaw],
                          !ambiguousSymbolExprRaws.contains(toRaw)
                    else {
                        continue
                    }
                    if let existing = symbolByExprRaw[toRaw] {
                        if existing != symbol, markAmbiguousSymbolExpr(toRaw) {
                            propagatedSymbols = true
                        }
                    } else {
                        symbolByExprRaw[toRaw] = symbol
                        propagatedSymbols = true
                    }
                }
            }

            func isFlowTransformEmitCall(_ callee: InternedString, _ arguments: [KIRExprID]) -> Bool {
                guard callee == kkFlowEmitName, arguments.count == 3 else {
                    return false
                }
                guard let tagExpr = module.arena.expr(arguments[2]),
                      case let .intLiteral(tagValue) = tagExpr,
                      tagValue == RuntimeFlowTag.map.rawValue ||
                      tagValue == RuntimeFlowTag.filter.rawValue ||
                      tagValue == RuntimeFlowTag.take.rawValue ||
                      tagValue == RuntimeFlowTag.transform.rawValue ||
                      tagValue == RuntimeFlowTag.takeWhile.rawValue ||
                      tagValue == RuntimeFlowTag.dropWhile.rawValue ||
                      tagValue == RuntimeFlowTag.buffer.rawValue ||
                      tagValue == RuntimeFlowTag.conflate.rawValue ||
                      tagValue == RuntimeFlowTag.flowOn.rawValue ||
                      tagValue == RuntimeFlowTag.debounce.rawValue ||
                      tagValue == RuntimeFlowTag.sample.rawValue ||
                      tagValue == RuntimeFlowTag.catchHandler.rawValue ||
                      tagValue == RuntimeFlowTag.retry.rawValue ||
                      tagValue == RuntimeFlowTag.retryWhen.rawValue
                else {
                    return false
                }
                return true
            }

            // KSP-CAP-010 / KSP-499 Stage 3: only treat a call as a synthetic
            // Flow intrinsic when the callee symbol is unresolved, synthetic,
            // or a known kk_flow_* bridge function. Real bundled/user Kotlin
            // declarations for these names must not be silently overwritten.
            func hasRealDeclaration(_ symbol: SymbolID?) -> Bool {
                return self.hasRealDeclaration(symbol, in: ctx)
            }
            let kkFlowBridgeNames: Set<InternedString> = [
                kkFlowCreateName,
                kkFlowEmitName, kkFlowCollectName, kkFlowCollectLatestName,
                kkFlowToListName, kkFlowFirstName, kkFlowSingleName,
            ]
            func isFlowRewriteCandidate(_ symbol: SymbolID?, _ callee: InternedString) -> Bool {
                if kkFlowBridgeNames.contains(callee) { return true }
                return !hasRealDeclaration(symbol)
            }

            var changed = true
            while changed {
                changed = false

                for instruction in function.body {
                    switch instruction {
                    case let .call(symbol, callee, arguments, result, _, _, _, _):
                        if let result, !flowExprIDs.contains(result.rawValue), isFlowClassResultType(result) {
                            if markFlowExpr(result) { changed = true }
                        }
                        if callee == flowName,
                           arguments.count == 1,
                           isFlowRewriteCandidate(symbol, callee)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == kkFlowCreateName, arguments.count == 2 {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           isFlowTransformEmitCall(callee, arguments) {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == singleName,
                           arguments.isEmpty,
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == mapName || callee == filterName || callee == takeName ||
                            callee == catchName || callee == retryName || callee == retryWhenName,
                           arguments.count == 2 ||
                            ((callee == mapName || callee == filterName || callee == catchName ||
                                callee == retryWhenName) && arguments.count == 3),
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           [transformName, takeWhileName, dropWhileName, flatMapConcatName, flatMapMergeName, flatMapLatestName, bufferName, flowOnName, debounceName, sampleName].contains(callee),
                           arguments.count >= 2,
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == conflateName,
                           arguments.count == 1,
                           let flowHandleArg = arguments.first,
                           flowExprIDs.contains(flowHandleArg.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           [combineName, zipName, mergeName].contains(callee) {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == collectName || callee == kkFlowCollectName || callee == collectLatestName,
                           arguments.count == 2 || arguments.count == 3,
                           let flowHandleArg = arguments.first
                        {
                            if flowExprIDs.insert(flowHandleArg.rawValue).inserted {
                                changed = true
                            }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == singleName,
                           arguments.isEmpty,
                           let flowHandleArg = arguments.first
                        {
                            if flowExprIDs.insert(flowHandleArg.rawValue).inserted {
                                changed = true
                            }
                            continue
                        }
                        if callee == emitName,
                           arguments.count == 1,
                           isFlowScopeFunction(function),
                           isFlowRewriteCandidate(symbol, callee)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }

                    case let .virtualCall(symbol, callee, receiver, arguments, result, _, _, _):
                        if !flowExprIDs.contains(receiver.rawValue), isFlowClassResultType(receiver) {
                            if markFlowExpr(receiver) { changed = true }
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == mapName || callee == filterName || callee == takeName ||
                            callee == catchName || callee == retryName || callee == retryWhenName,
                           arguments.count == 1,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           [transformName, takeWhileName, dropWhileName, flatMapConcatName, flatMapMergeName, flatMapLatestName, bufferName, flowOnName, debounceName, sampleName].contains(callee),
                           arguments.count == 1,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == conflateName,
                           arguments.isEmpty,
                           flowExprIDs.contains(receiver.rawValue)
                        {
                            if markFlowExpr(result) { changed = true }
                            continue
                        }
                        if isFlowRewriteCandidate(symbol, callee),
                           callee == collectName || callee == collectLatestName,
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
                    callee == flowName ||
                        callee == emitName || callee == collectName || callee == collectLatestName ||
                        callee == mapName || callee == filterName || callee == takeName ||
                        callee == transformName || callee == takeWhileName || callee == dropWhileName ||
                        callee == flatMapConcatName || callee == flatMapMergeName || callee == flatMapLatestName ||
                        callee == combineName || callee == zipName || callee == mergeName ||
                        callee == bufferName || callee == conflateName || callee == flowOnName ||
                        callee == debounceName || callee == sampleName ||
                        callee == toListName || callee == firstName || callee == singleName ||
                        callee == kkFlowCreateName || callee == kkFlowEmitName || callee == kkFlowCollectName ||
                        callee == kkFlowCollectLatestName ||
                        callee == kkFlowToListName || callee == kkFlowFirstName || callee == kkFlowSingleName ||
                        callee == kkChannelFlowCreateName || callee == kkCallbackFlowCreateName
                case let .virtualCall(_, callee, _, _, _, _, _, _):
                    callee == mapName || callee == filterName || callee == takeName || callee == collectName ||
                        callee == collectLatestName ||
                        callee == transformName || callee == takeWhileName || callee == dropWhileName ||
                        callee == flatMapConcatName || callee == flatMapMergeName || callee == flatMapLatestName ||
                        callee == bufferName || callee == conflateName || callee == flowOnName ||
                        callee == debounceName || callee == sampleName ||
                        callee == catchName || callee == retryName || callee == retryWhenName ||
                        callee == toListName || callee == firstName || callee == singleName
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
                case let .call(symbol, callee, arguments, _, _, _, _, _):
                    if isFlowRewriteCandidate(symbol, callee),
                   callee == mapName || callee == filterName || callee == takeName ||
                        callee == catchName || callee == retryName || callee == retryWhenName,
                       arguments.count == 2 ||
                        ((callee == mapName || callee == filterName || callee == catchName ||
                            callee == retryWhenName) && arguments.count == 3)
                    {
                        markConsume(arguments[0])
                        continue
                    }
                    if isFlowRewriteCandidate(symbol, callee),
                       callee == collectName || callee == kkFlowCollectName || callee == collectLatestName,
                       arguments.count == 2 || arguments.count == 3
                    {
                        markConsume(arguments[0])
                        continue
                    }
                    if isFlowRewriteCandidate(symbol, callee),
                       callee == toListName || callee == firstName || callee == singleName ||
                        callee == kkFlowToListName || callee == kkFlowFirstName || callee == kkFlowSingleName,
                       !arguments.isEmpty {
                        markConsume(arguments[0])
                        continue
                    }
                    if isFlowRewriteCandidate(symbol, callee),
                       isFlowTransformEmitCall(callee, arguments), arguments.count == 3 {
                        markConsume(arguments[0])
                    }
                case let .virtualCall(symbol, callee, receiver, arguments, _, _, _, _):
                    if isFlowRewriteCandidate(symbol, callee),
                   callee == mapName || callee == filterName || callee == takeName ||
                        callee == catchName || callee == retryName || callee == retryWhenName ||
                        callee == collectName ||
                        callee == collectLatestName,
                       arguments.count == 1
                    {
                        markConsume(receiver)
                    }
                    if isFlowRewriteCandidate(symbol, callee),
                   callee == toListName || callee == firstName || callee == singleName, arguments.isEmpty {
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
                collectLatest: collectLatestName,
                map: mapName,
                filter: filterName,
                take: takeName,
                transform: transformName,
                single: singleName,
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
                catchHandler: catchName,
                retry: retryName,
                retryWhen: retryWhenName,
                toList: toListName,
                first: firstName,
                kkFlowCreate: kkFlowCreateName,
                kkFlowEmit: kkFlowEmitName,
                kkFlowCollect: kkFlowCollectName,
                kkFlowCollectLatest: kkFlowCollectLatestName,
                kkFlowRetain: kkFlowRetainName,
                kkFlowRelease: kkFlowReleaseName,
                kkFlowToList: kkFlowToListName,
                kkFlowFirst: kkFlowFirstName,
                kkFlowSingle: kkFlowSingleName,
                kkFlowZip: kkFlowZipName,
                kkFlowCombine: kkFlowCombineName,
                kkFlowMerge: kkFlowMergeName,
                kkFlowFlatMapConcat: kkFlowFlatMapConcatName,
                kkFlowFlatMapMerge: kkFlowFlatMapMergeName,
                kkFlowFlatMapLatest: kkFlowFlatMapLatestName
            )
            let loweredBody = rewriteFlowInstructions(
                originalBody: function.body,
                originalLocations: function.instructionLocations,
                module: module,
                ctx: ctx,
                flowExprIDs: &flowExprIDs,
                remainingConsumes: &remainingConsumes,
                symbolByExprRaw: symbolByExprRaw,
                names: names,
                isFlowScopeFunction: isFlowScopeFunction(function)
            )

            updated.replaceBody(cleanUpOwnedFlows(loweredBody, module: module, ctx: ctx, freshFunctions: freshFunctions))
            return updated
        }
        module.arena.transformFunctions(transformFunction)
    }
}
