/// Which body a symbol maps to can change during scheduling; the
/// classification (`origin`, `isBodyless`, membership in each table) is fixed
/// after recursive auto-inline declarations regain their native bodies.
///
/// Imported bodies are deferred: the store hands the index a descriptor
/// (resolved artifact path, signature, declared name) per symbol instead of a
/// parsed body, and the index asks the store to read + parse + materialize a
/// body only when `inlineTarget` first resolves a call to it. A descriptor
/// that fails to materialize is dropped from the target set, the by-name
/// candidates, `bodylessInlineSymbols`, and `origins` — the same absence a
/// failed eager import produced.
///
/// Two tables cover the two lookup roles:
///
/// * `inlineFunctionsBySymbol` -- expansion targets: module `inline`
///   declarations plus materialized imported inline bodies, keyed by callee
///   symbol. Only this table can supply the body spliced at a `.call` site.
///   Deferred descriptors fill it on first use.
/// * `allFunctionsBySymbol` -- every module-declared function (regular
///   functions, `inline` declarations, and lambda bodies), which is the table
///   lambda resolution uses to map a `symbolRef` argument back to its body.
///
/// A symbol can appear in both tables (a module `inline` function), and in
/// the rare collision case can map to *different* bodies in each (an imported
/// inline body filling the target table where the module declares the same
/// symbol non-inline), so the tables stay separate rather than merging into a
/// single entry record.
final class InlineExpansionIndex {
    enum Origin: Sendable {
        case module
        case imported
    }

    private(set) var inlineFunctionsBySymbol: [SymbolID: KIRFunction]

    /// Never contains an imported body.
    private(set) var allFunctionsBySymbol: [SymbolID: KIRFunction]

    /// Callees whose body never reaches an object file: module
    /// `isInlineOnly` auto-inline functions plus every imported inline
    /// symbol (the metadata does not carry `isInlineOnly`, and an artifact
    /// omits auto-inline bodies). A call to one of these must be expanded
    /// away rather than left for the linker. Deferred descriptors count too:
    /// their body will be parsed on demand when a call resolves to them.
    private(set) var bodylessInlineSymbols: Set<SymbolID>

    /// Pre-expansion bodies for every schedulable symbol -- the union of
    /// both tables, with the module declaration winning on collision --
    /// frozen when the body enters the index. Deferred descriptors join on
    /// materialization, so a parsed imported body is scheduled by the
    /// dependency worklist just like an eagerly imported one was. The
    /// scheduler expands each original once against prepared callee snapshots.
    private(set) var originalBodies: [SymbolID: KIRFunction]

    private(set) var origins: [SymbolID: Origin]

    private let importedStore: ImportedInlineFunctionStore

    private let arena: KIRArena

    private var cachedInlineFunctionsByName: [InternedString: [SymbolID]]?

    /// Materialized imported bodies fill only symbols no module `inline`
    /// declaration owns; every imported symbol — materialized or still a
    /// descriptor — is marked bodyless.
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
        // A template containing enumValues cannot execute before specialization.
        // Include inline wrappers and default stubs transitively, so expansion
        // budget failures diagnose instead of falling back to native templates.
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

    /// Auto-inlining is optional for ordinary declarations. A bodyless call
    /// cycle cannot be expanded, so retain native entry points for its
    /// non-inline declarations before scheduling any snapshots. Explicit
    /// inline templates, imported bodies and non-local-return lambdas keep
    /// their mandatory-expansion contract.
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

    /// Resolves a deferred descriptor: read + parse the artifact and rebind
    /// it into the module arena, then fold it into the target table and the
    /// schedulable originals so the worklist sees it exactly like an
    /// eagerly imported body. On failure the symbol drops out of every set
    /// the eager path would never have put it in.
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
        return function
    }

    /// By-name view of the expansion targets, consulted only at
    /// symbol-unknown call sites. Deferred descriptors contribute their
    /// declared name without a parse. Candidates are sorted by symbol before
    /// grouping so candidate order within each name never depends on
    /// dictionary enumeration order.
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

    /// The bodyless callees `symbol`'s current body still calls, as
    /// resolved-symbol edges. Only `.call` instructions carrying a callee
    /// symbol create edges: a symbol-known call binds to exactly that
    /// symbol, while a symbol-unknown call resolves its own name fallback
    /// at the call site and is not a dependency here. Self-calls are
    /// ignored, matching the caller-side recursion guard.
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

    /// The symbol raw value is a unique final tiebreaker, so the order is
    /// total and the resulting schedule is the same regardless of
    /// enumeration order.
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

    /// Bodyless symbols whose expansion can never terminate because a call
    /// cycle of bodyless callees is reachable from them in the *current*
    /// bodies -- self-loops and mutual recursion included. Unlike
    /// `bodylessCallees`, self-calls count as edges here: a bodyless
    /// self-call is a one-node cycle. A caller whose residue callee is in
    /// this set cannot converge no matter how many rounds run; a callee
    /// outside it simply outgrew the round bounds.
    /// Native-body recovery also follows emitted inline wrappers: expanding
    /// such a wrapper can expose a recursive call to an auto-inline caller.
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
        // Backward closure: a callee that can reach a cyclic one inherits
        // the same non-termination even though it is not on the cycle.
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
    }
}
