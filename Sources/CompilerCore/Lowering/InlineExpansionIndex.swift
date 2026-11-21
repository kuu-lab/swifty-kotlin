final class InlineExpansionIndex {
    enum Origin: Sendable {
        case module
        case imported
    }

    private(set) var inlineFunctionsBySymbol: [SymbolID: KIRFunction]

    private(set) var allFunctionsBySymbol: [SymbolID: KIRFunction]

    private(set) var bodylessInlineSymbols: Set<SymbolID>

    private(set) var originalBodies: [SymbolID: KIRFunction]

    private(set) var origins: [SymbolID: Origin]

    private let importedStore: ImportedInlineFunctionStore

    private let arena: KIRArena

    private var cachedInlineFunctionsByName: [InternedString: [SymbolID]]?

    init(module: KIRModule, importedInlineFunctions: ImportedInlineFunctionStore, reifiedEnumValuesCallee: InternedString? = nil) {
        var inlineFunctionsBySymbol: [SymbolID: KIRFunction] = [:]
        var allFunctionsBySymbol: [SymbolID: KIRFunction] = [:]
        var origins: [SymbolID: Origin] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            allFunctionsBySymbol[function.symbol] = function
            if function.isInline {
                inlineFunctionsBySymbol[function.symbol] = function
                origins[function.symbol] = .module
            }
        }
        for symbol in importedInlineFunctions.functions.keys.sorted(by: { $0.rawValue < $1.rawValue })
            where inlineFunctionsBySymbol[symbol] == nil
        {
            inlineFunctionsBySymbol[symbol] = importedInlineFunctions.functions[symbol]
            origins[symbol] = .imported
        }
        for symbol in importedInlineFunctions.descriptors.keys
            where inlineFunctionsBySymbol[symbol] == nil
        {
            origins[symbol] = .imported
        }
        var bodyless = Set(inlineFunctionsBySymbol.filter { $0.value.isInlineOnly }.keys)
        if let reifiedEnumValuesCallee {
            var templates = Set(inlineFunctionsBySymbol.values.filter { function in
                function.body.contains {
                    if case let .call(_, callee, _, _, _, _, _, _) = $0 { return callee == reifiedEnumValuesCallee }
                    return false
                }
            }.map(\.symbol))
            var changed = true
            while changed {
                changed = false
                for function in inlineFunctionsBySymbol.values where !templates.contains(function.symbol) {
                    if function.body.contains(where: {
                        if case let .call(symbol?, _, _, _, _, _, _, _) = $0 { return templates.contains(symbol) }
                        return false
                    }) {
                        templates.insert(function.symbol)
                        changed = true
                    }
                }
            }
            bodyless.formUnion(templates)
        }
        bodyless.formUnion(importedInlineFunctions.functions.keys)
        bodyless.formUnion(importedInlineFunctions.descriptors.keys)
        var originalBodies = allFunctionsBySymbol
        for (symbol, function) in inlineFunctionsBySymbol.sorted(by: { $0.key.rawValue < $1.key.rawValue })
            where originalBodies[symbol] == nil
        {
            originalBodies[symbol] = function
        }
        self.inlineFunctionsBySymbol = inlineFunctionsBySymbol
        self.allFunctionsBySymbol = allFunctionsBySymbol
        self.bodylessInlineSymbols = bodyless
        self.originalBodies = originalBodies
        self.origins = origins
        self.importedStore = importedInlineFunctions
        self.arena = module.arena
    }

    func origin(of symbol: SymbolID) -> Origin? {
        origins[symbol]
    }

    func isBodyless(_ symbol: SymbolID) -> Bool {
        bodylessInlineSymbols.contains(symbol)
    }

    func isExpansionTarget(_ symbol: SymbolID) -> Bool {
        inlineFunctionsBySymbol[symbol] != nil || importedStore.descriptors[symbol] != nil
    }

    func retainRecursiveAutoInlineBodies(module: KIRModule, sema: SemaModule?) {
        guard let sema else { return }
        let declaredSymbols = Set(sema.bindings.declSymbols.values)
        let retained = recursiveBodylessCallees(includingEmittedInlineFunctions: true).filter { symbol in
            guard origins[symbol] == .module,
                  declaredSymbols.contains(symbol),
                  let declaration = sema.symbols.symbol(symbol),
                  declaration.kind == .function,
                  !declaration.flags.contains(.inlineFunction)
            else { return false }
            return allFunctionsBySymbol[symbol]?.isInlineOnly == true
        }
        guard !retained.isEmpty else { return }
        module.arena.transformFunctions { function in
            guard retained.contains(function.symbol) else { return function }
            let emitted = KIRFunction(
                symbol: function.symbol, name: function.name, params: function.params,
                returnType: function.returnType, body: function.body,
                isSuspend: function.isSuspend, isInline: false, isInlineOnly: false,
                isTailrec: function.isTailrec, sourceRange: function.sourceRange,
                instructionLocations: function.instructionLocations
            )
            allFunctionsBySymbol[function.symbol] = emitted
            originalBodies[function.symbol] = emitted
            inlineFunctionsBySymbol[function.symbol] = nil
            bodylessInlineSymbols.remove(function.symbol)
            origins[function.symbol] = nil
            return emitted
        }
        cachedInlineFunctionsByName = nil
    }

    /// The name fallback only applies to calls whose callee symbol is
    /// unknown here. A call with a *known* callee symbol that isn't an
    /// expansion target in this module must not be redirected to a
    /// same-named inline overload from an unrelated receiver type (e.g.
    /// `Mutex.withLock` vs `Lock.withLock`, or a synthetic/runtime-dispatched
    /// member such as the generic `Iterable<T>.iterator()` used inside
    /// `reduce` vs an unrelated bundled `Map<K, V>.iterator()` -- see
    /// KSP-1011). A known symbol that resolves to no target is exactly as
    /// "not ours to rename" as one resolving to a known non-inline function:
    /// its own resolution (external link / virtual dispatch) still applies
    /// once this pass is done with it.
    func inlineTarget(
        callSymbol: SymbolID?,
        callee: InternedString,
        inlineFunctionsByName: [InternedString: [SymbolID]]
    ) -> KIRFunction? {
        if let callSymbol {
            if let target = inlineFunctionsBySymbol[callSymbol] {
                return target
            }
            guard importedStore.descriptors[callSymbol] != nil else {
                return nil
            }
            return materializeImportedBody(for: callSymbol)
        }
        guard let candidates = inlineFunctionsByName[callee], candidates.count == 1 else {
            return nil
        }
        let symbol = candidates[0]
        if let target = inlineFunctionsBySymbol[symbol] {
            return target
        }
        guard importedStore.descriptors[symbol] != nil else {
            return nil
        }
        return materializeImportedBody(for: symbol)
    }

    private func materializeImportedBody(for symbol: SymbolID) -> KIRFunction? {
        cachedInlineFunctionsByName = nil
        guard let function = importedStore.function(for: symbol, arena: arena) else {
            origins[symbol] = nil
            bodylessInlineSymbols.remove(symbol)
            return nil
        }
        inlineFunctionsBySymbol[symbol] = function
        if originalBodies[symbol] == nil {
            originalBodies[symbol] = function
        }
        calleeFactsCache[symbol] = nil
        return function
    }

    var inlineFunctionsByName: [InternedString: [SymbolID]] {
        if let cachedInlineFunctionsByName { return cachedInlineFunctionsByName }
        var groups: [InternedString: [SymbolID]] = [:]
        for (symbol, function) in inlineFunctionsBySymbol.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            groups[function.name, default: []].append(symbol)
        }
        for (symbol, descriptor) in importedStore.descriptors.sorted(by: { $0.key.rawValue < $1.key.rawValue })
            where inlineFunctionsBySymbol[symbol] == nil
        {
            groups[descriptor.name, default: []].append(symbol)
        }
        cachedInlineFunctionsByName = groups
        return groups
    }

    func bodylessCallees(of symbol: SymbolID) -> Set<SymbolID> {
        guard let body = (allFunctionsBySymbol[symbol] ?? inlineFunctionsBySymbol[symbol])?.body else {
            return []
        }
        var callees: Set<SymbolID> = []
        for instruction in body {
            guard case let .call(callee, _, _, _, _, _, _, _) = instruction,
                  let callee, callee != symbol,
                  bodylessInlineSymbols.contains(callee)
            else {
                continue
            }
            callees.insert(callee)
        }
        return callees
    }

    /// Ordering compares the frozen original bodies via
    /// `snapshotExpansionOrder`, so it never depends on dictionary
    /// enumeration order -- expansion appends expressions to the module
    /// arena, and enumeration order must not choose expression IDs.
    func pendingBodylessCallers(interner: StringInterner) -> [SymbolID] {
        originalBodies
            .filter { !bodylessCallees(of: $0.key).isEmpty }
            .sorted { Self.snapshotExpansionOrder($0.value, $1.value, interner: interner) }
            .map(\.key)
    }

    static func snapshotExpansionOrder(
        _ lhs: KIRFunction,
        _ rhs: KIRFunction,
        interner: StringInterner
    ) -> Bool {
        let lhsName = interner.resolve(lhs.name)
        let rhsName = interner.resolve(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }
        if lhs.params.count != rhs.params.count { return lhs.params.count < rhs.params.count }
        if let lhsRange = lhs.sourceRange, let rhsRange = rhs.sourceRange {
            if lhsRange.start.file.rawValue != rhsRange.start.file.rawValue {
                return lhsRange.start.file.rawValue < rhsRange.start.file.rawValue
            }
            if lhsRange.start.offset != rhsRange.start.offset {
                return lhsRange.start.offset < rhsRange.start.offset
            }
            if lhsRange.end.offset != rhsRange.end.offset {
                return lhsRange.end.offset < rhsRange.end.offset
            }
        } else if lhs.sourceRange != nil {
            return false
        } else if rhs.sourceRange != nil {
            return true
        }
        return lhs.symbol.rawValue < rhs.symbol.rawValue
    }

    /// Applies the same binding rule as `inlineTarget` (a known symbol binds
    /// to its own snapshot only; a symbol-unknown call takes the unique
    /// by-name candidate) without materializing a deferred body.
    ///
    /// A known symbol is only mandatory while the callee text still names
    /// that symbol's emitted identity -- the declared name or its external
    /// link name. Codegen binds `.call` by callee text, so a call whose
    /// callee was rewritten to a different name (e.g. a CallLowerer bridge
    /// rewrite that keeps the original symbol) no longer binds to the
    /// bodyless symbol: leaving it is correct, and only the name-based rule
    /// below can still mark it.
    func isMandatoryExpansionCall(
        callSymbol: SymbolID?,
        callee: InternedString,
        inlineFunctionsByName: [InternedString: [SymbolID]],
        interner: StringInterner,
        externalLinkName: (SymbolID) -> String?
    ) -> Bool {
        if let callSymbol {
            guard bodylessInlineSymbols.contains(callSymbol) else {
                return false
            }
            let declaredName = allFunctionsBySymbol[callSymbol]?.name
                ?? inlineFunctionsBySymbol[callSymbol]?.name
                ?? importedStore.descriptors[callSymbol]?.name
            if callee == declaredName || declaredName == nil {
                return true
            }
            if let linkName = externalLinkName(callSymbol),
               interner.intern(linkName) == callee {
                return true
            }
        }
        guard let candidates = inlineFunctionsByName[callee], candidates.count == 1 else {
            return false
        }
        return bodylessInlineSymbols.contains(candidates[0])
    }

    func recursiveBodylessCallees(includingEmittedInlineFunctions: Bool = false) -> Set<SymbolID> {
        let graphSymbols = includingEmittedInlineFunctions
            ? bodylessInlineSymbols.union(inlineFunctionsBySymbol.keys)
            : bodylessInlineSymbols
        var edges: [SymbolID: Set<SymbolID>] = [:]
        for symbol in graphSymbols {
            guard let body = (allFunctionsBySymbol[symbol] ?? inlineFunctionsBySymbol[symbol])?.body else {
                continue
            }
            var targets: Set<SymbolID> = []
            for instruction in body {
                guard case let .call(callee, _, _, _, _, _, _, _) = instruction,
                      let callee, graphSymbols.contains(callee)
                else {
                    continue
                }
                targets.insert(callee)
            }
            if !targets.isEmpty {
                edges[symbol] = targets
            }
        }
        var cyclic: Set<SymbolID> = []
        for (symbol, targets) in edges {
            var visited: Set<SymbolID> = []
            var stack = Array(targets)
            while let next = stack.popLast() {
                if next == symbol {
                    cyclic.insert(symbol)
                    break
                }
                guard visited.insert(next).inserted else { continue }
                stack.append(contentsOf: edges[next] ?? [])
            }
        }
        var reaching = cyclic
        var reverseEdges: [SymbolID: [SymbolID]] = [:]
        for (from, targets) in edges {
            for to in targets {
                reverseEdges[to, default: []].append(from)
            }
        }
        var stack = Array(cyclic)
        while let node = stack.popLast() {
            for predecessor in reverseEdges[node] ?? [] where reaching.insert(predecessor).inserted {
                stack.append(predecessor)
            }
        }
        return reaching
    }

    func recordExpansion(of symbol: SymbolID, to function: KIRFunction) {
        if inlineFunctionsBySymbol[symbol] != nil {
            inlineFunctionsBySymbol[symbol] = function
        }
        if allFunctionsBySymbol[symbol] != nil {
            allFunctionsBySymbol[symbol] = function
        }
        calleeFactsCache[symbol] = nil
    }

    private var calleeFactsCache: [SymbolID: InlineCalleeFacts] = [:]

    func facts(for function: KIRFunction, sema: SemaModule?) -> InlineCalleeFacts {
        if let cached = calleeFactsCache[function.symbol] {
            return cached
        }
        let facts = InlineCalleeFacts(function: function, sema: sema)
        calleeFactsCache[function.symbol] = facts
        return facts
    }
}

struct InlineCalleeFacts {
    var reboundParamSymbols: Set<SymbolID> = []
    var bodyOwnsNonLocalReturn = false
    var inlineReturnCount = 0
    var hasReturnIfEqual = false
    var hasValueReturn = false
    var mergeSlotExprs: Set<KIRExprID> = []
    var lambdaParamSymbols: Set<SymbolID> = []
    var lambdaParamByCalleeName: [InternedString: SymbolID] = [:]
    var usesErasedLambdaABI = false
    var bodyLabelIDs: [Int32] = []

    init(function: KIRFunction, sema: SemaModule?) {
        var storageSymbols: [KIRExprID: SymbolID] = [:]
        for instruction in function.body {
            guard case let .constValue(expr, .symbolRef(symbol)) = instruction else { continue }
            storageSymbols[expr] = symbol
        }
        var rebound: Set<SymbolID> = []
        var mergeWriteCounts: [KIRExprID: Int] = [:]
        for instruction in function.body {
            let reboundWritten: [KIRExprID]
            switch instruction {
            case let .copy(_, to):
                reboundWritten = [to]
            case let .constValue(result, value):
                if case let .symbolRef(bound) = value, storageSymbols[result] == bound {
                    reboundWritten = []
                } else {
                    reboundWritten = [result]
                }
            case let .call(_, _, _, result, _, thrownResult, _, _),
                 let .virtualCall(_, _, _, _, result, _, thrownResult, _):
                reboundWritten = [result, thrownResult].compactMap { $0 }
            case let .beginNonLocalReturnScope(value, _, function):
                reboundWritten = function != nil ? [value] : []
            default:
                reboundWritten = InlineExprAliasing.definedResult(in: instruction).map { [$0] } ?? []
            }
            for expr in reboundWritten {
                if let symbol = storageSymbols[expr] {
                    rebound.insert(symbol)
                }
            }

            let mergeWritten: KIRExprID? = switch instruction {
            case let .copy(_, to): to
            case let .call(_, _, _, result, _, _, _, _): result
            case let .virtualCall(_, _, _, _, result, _, _, _): result
            case let .binary(_, _, _, result): result
            case let .unary(_, _, result): result
            case let .constValue(result, _): result
            case let .nullAssert(_, result): result
            case let .loadGlobal(result, _): result
            default: nil
            }
            if let mergeWritten {
                mergeWriteCounts[mergeWritten, default: 0] += 1
            }

            switch instruction {
            case .returnUnit:
                inlineReturnCount += 1
            case .returnValue:
                inlineReturnCount += 1
                hasValueReturn = true
            case .returnIfEqual:
                inlineReturnCount += 1
                hasReturnIfEqual = true
            case let .nonLocalReturn(_, target):
                if target == .function(function.symbol) {
                    bodyOwnsNonLocalReturn = true
                }
            case let .label(id):
                bodyLabelIDs.append(id)
            default:
                break
            }
        }
        reboundParamSymbols = rebound
        mergeSlotExprs = Set(mergeWriteCounts.filter { $0.value > 1 }.keys)

        guard let sema else { return }
        for param in function.params {
            if case .functionType = sema.types.kind(of: param.type) {
                lambdaParamSymbols.insert(param.symbol)
                if let symbolInfo = sema.symbols.symbol(param.symbol) {
                    lambdaParamByCalleeName[symbolInfo.name] = param.symbol
                }
            }
        }
        usesErasedLambdaABI = !lambdaParamSymbols.isEmpty
            && sema.symbols.symbol(function.symbol)?.flags.contains(.importedLibrary) == true
    }
}
