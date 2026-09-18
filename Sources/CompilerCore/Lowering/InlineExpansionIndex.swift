/// Expansion-target index for the inline pass: every function body the pass
/// can splice into a caller, keyed by `SymbolID`, plus the classification and
/// dependency queries the scheduling loops consume.
///
/// The index is built once per module from the arena declarations and the
/// imported inline-KIR table, then updated in place as nested bodyless calls
/// are expanded. Which body a symbol maps to can change between rounds; the
/// classification (`origin`, `isBodyless`, membership in each table) is fixed
/// at build time.
///
/// Two tables cover the two lookup roles:
///
/// * `inlineFunctionsBySymbol` -- expansion targets: module `inline`
///   declarations plus imported inline bodies, keyed by callee symbol. Only
///   this table can supply the body spliced at a `.call` site.
/// * `allFunctionsBySymbol` -- every module-declared function (regular
///   functions, `inline` declarations, and lambda bodies), which is the table
///   lambda resolution uses to map a `symbolRef` argument back to its body.
///
/// A symbol can appear in both tables (a module `inline` function), and in
/// the rare collision case can map to *different* bodies in each (an imported
/// inline body filling the target table where the module declares the same
/// symbol non-inline), so the tables stay separate rather than merging into a
/// single entry record.
struct InlineExpansionIndex {
    /// Where an expansion target's body came from.
    enum Origin: Sendable {
        /// Declared `inline` in this module's arena.
        case module
        /// Restored from an imported library's inline-KIR metadata.
        case imported
    }

    /// Expansion targets keyed by callee symbol: module `inline`
    /// declarations plus imported inline bodies.
    private(set) var inlineFunctionsBySymbol: [SymbolID: KIRFunction]

    /// Module-declared bodies keyed by symbol: every function in the arena
    /// -- regular functions, `inline` declarations, and lambda bodies. The
    /// lookup lambda resolution uses; never contains an imported body.
    private(set) var allFunctionsBySymbol: [SymbolID: KIRFunction]

    /// Callees whose body never reaches an object file: module
    /// `isInlineOnly` auto-inline functions plus every imported inline
    /// symbol (the metadata does not carry `isInlineOnly`, and an artifact
    /// omits auto-inline bodies). A call to one of these must be expanded
    /// away rather than left for the linker.
    let bodylessInlineSymbols: Set<SymbolID>

    /// Pre-expansion bodies for every schedulable symbol -- the union of
    /// both tables, with the module declaration winning on collision --
    /// frozen when the index is built. Each scheduling round re-expands
    /// these originals against the improving snapshots so a body is never
    /// spliced twice.
    let originalBodies: [SymbolID: KIRFunction]

    /// Where each expansion target's body was sourced (`nil` for symbols
    /// that are not expansion targets).
    private(set) var origins: [SymbolID: Origin]

    /// Snapshot the module's functions and the imported inline table.
    /// Imported bodies fill only symbols no module `inline` declaration
    /// owns; every imported symbol is still marked bodyless.
    init(module: KIRModule, importedInlineFunctions: [SymbolID: KIRFunction]) {
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
        for symbol in importedInlineFunctions.keys.sorted(by: { $0.rawValue < $1.rawValue })
            where inlineFunctionsBySymbol[symbol] == nil
        {
            inlineFunctionsBySymbol[symbol] = importedInlineFunctions[symbol]
            origins[symbol] = .imported
        }
        var bodyless = Set(inlineFunctionsBySymbol.filter { $0.value.isInlineOnly }.keys)
        bodyless.formUnion(importedInlineFunctions.keys)
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
    }

    // MARK: - Classification

    /// Where the expansion target for `symbol` came from: `.module` for a
    /// module `inline` declaration, `.imported` for a body restored from
    /// library metadata. `nil` when `symbol` is not an expansion target at
    /// all (a regular module function or lambda body).
    func origin(of symbol: SymbolID) -> Origin? {
        origins[symbol]
    }

    /// Whether `symbol` is a bodyless callee whose calls must be expanded.
    func isBodyless(_ symbol: SymbolID) -> Bool {
        bodylessInlineSymbols.contains(symbol)
    }

    /// Whether `symbol` maps to an expansion target (module `inline` or
    /// imported inline), as opposed to a module-only body that lambda
    /// resolution can still reach through `allFunctionsBySymbol`.
    func isExpansionTarget(_ symbol: SymbolID) -> Bool {
        inlineFunctionsBySymbol[symbol] != nil
    }

    // MARK: - Call-site target resolution

    /// The expansion target for a `.call` carrying `callSymbol` / `callee`.
    ///
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
        inlineFunctionsByName: [InternedString: [KIRFunction]]
    ) -> KIRFunction? {
        if let callSymbol, let target = inlineFunctionsBySymbol[callSymbol] {
            return target
        }
        if callSymbol != nil {
            return nil
        }
        guard let candidates = inlineFunctionsByName[callee], candidates.count == 1 else {
            return nil
        }
        return candidates[0]
    }

    /// By-name view of the expansion targets, consulted only at
    /// symbol-unknown call sites. Targets are sorted by symbol before
    /// grouping so candidate order within each name never depends on
    /// dictionary enumeration order.
    var inlineFunctionsByName: [InternedString: [KIRFunction]] {
        Dictionary(
            grouping: inlineFunctionsBySymbol.values.sorted(by: { $0.symbol.rawValue < $1.symbol.rawValue }),
            by: \.name
        )
    }

    // MARK: - Bodyless dependency info

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

    /// Snapshots whose current body still calls a bodyless callee, in
    /// deterministic expansion order. Ordering compares the frozen original
    /// bodies via `snapshotExpansionOrder`, so it never depends on
    /// dictionary enumeration order -- expansion appends expressions to the
    /// module arena, and enumeration order must not choose expression IDs.
    func pendingBodylessCallers(interner: StringInterner) -> [SymbolID] {
        originalBodies
            .filter { !bodylessCallees(of: $0.key).isEmpty }
            .sorted { Self.snapshotExpansionOrder($0.value, $1.value, interner: interner) }
            .map(\.key)
    }

    /// Total order used to schedule snapshot expansion: resolved name, then
    /// parameter count, then source range, then symbol raw value. The symbol
    /// raw value is a unique final tiebreaker, so the order is total and the
    /// resulting schedule is the same regardless of enumeration order.
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

    // MARK: - Write-back

    /// Records an expanded snapshot for `symbol` in every table that holds
    /// it -- the module table and/or the expansion-target table.
    mutating func recordExpansion(of symbol: SymbolID, to function: KIRFunction) {
        if inlineFunctionsBySymbol[symbol] != nil {
            inlineFunctionsBySymbol[symbol] = function
        }
        if allFunctionsBySymbol[symbol] != nil {
            allFunctionsBySymbol[symbol] = function
        }
    }
}
