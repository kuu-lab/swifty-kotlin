final class SemaCacheContext {
    private var scopeCache: [ObjectIdentifier: [InternedString: [SymbolID]]] = [:]

    /// Retains scope objects whose identities are used as cache keys, preventing
    /// `ObjectIdentifier` reuse after a scope is deallocated.
    private var scopeRetainer: [ObjectIdentifier: Scope] = [:]

    func lookupInScope(_ name: InternedString, scope: Scope) -> [SymbolID] {
        let scopeKey = ObjectIdentifier(scope)
        if let nameCache = scopeCache[scopeKey], let cached = nameCache[name] {
            scopeHits += 1
            return cached
        }
        scopeMisses += 1
        let result = scope.lookup(name)
        scopeRetainer[scopeKey] = scope
        scopeCache[scopeKey, default: [:]][name] = result
        return result
    }

    /// Scope contents can grow while type checking local declarations. Any
    /// cached lookup may have walked through a scope whose parent was just
    /// updated, so discard scope results after such an insertion.
    func invalidateScopeLookups() {
        scopeCache.removeAll(keepingCapacity: true)
        scopeRetainer.removeAll(keepingCapacity: true)
    }

    private var symbolCache: [SymbolID: SemanticSymbol] = [:]

    private var symbolMissCache: Set<SymbolID> = []

    func symbol(_ id: SymbolID, in table: SymbolTable) -> SemanticSymbol? {
        if let cached = symbolCache[id] {
            return cached
        }
        if symbolMissCache.contains(id) {
            return nil
        }
        let result = table.symbol(id)
        if let result {
            symbolCache[id] = result
        } else {
            symbolMissCache.insert(id)
        }
        return result
    }

    /// Cache key for ``OverloadResolver.resolveCall``.
    ///
    /// Includes the current ``FunctionSignature`` of each candidate so that
    /// mutations to signatures during type checking (e.g. when a function's
    /// return type is inferred from its body) cause a cache miss rather than
    /// returning stale results.
    struct CallResolutionKey: Hashable, CustomStringConvertible {
        let candidates: [SymbolID]
        let candidateSignatures: [FunctionSignature?]
        let candidateDefaultOwners: [SymbolID?]
        let calleeName: InternedString
        let argTypes: [TypeID]
        let argLabels: [InternedString?]
        let argIsSpread: [Bool]
        let argIsTrailingLambda: [Bool?]
        let signedIntegerLiterals: [Int64?]
        let unsignedIntegerLiterals: [UInt64?]
        let explicitTypeArgs: [TypeID]
        let expectedType: TypeID?
        let elvisLhsExpectedTypeHint: Bool
        let elvisRhsCallResultTypeHint: TypeID?
        let implicitReceiverType: TypeID?
        let dispatchReceiverTypes: [TypeID]
        let boundObjectDispatchReceiverCandidates: Set<SymbolID>

        var description: String {
            return "\(calleeName):\(candidates.count)"
        }
    }

    private var callResolutionCache: [CallResolutionKey: ResolvedCall] = [:]

    func cachedCallResolution(for key: CallResolutionKey) -> ResolvedCall? {
        callResolutionCache[key]
    }

    /// Stores a resolution result in the cache.
    /// Results that contain a diagnostic are **not** cached because the diagnostic
    /// embeds source ranges from the specific call site.  Caching them would
    /// cause later call sites with the same key to receive diagnostics pointing
    /// at the wrong source location.
    func cacheCallResolution(_ result: ResolvedCall, for key: CallResolutionKey) {
        guard result.diagnostic == nil else { return }
        callResolutionCache[key] = result
    }

    static func makeCallResolutionKey(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        symbols: SymbolTable,
        defaultArgumentOwners: [SymbolID: SymbolID] = [:]
    ) -> CallResolutionKey {
        let sorted = candidates.sorted(by: { $0.rawValue < $1.rawValue })
        return CallResolutionKey(
            candidates: sorted,
            candidateSignatures: sorted.map { symbols.functionSignature(for: $0) },
            candidateDefaultOwners: sorted.map { defaultArgumentOwners[$0] },
            calleeName: call.calleeName,
            argTypes: call.args.map(\.type),
            argLabels: call.args.map(\.label),
            argIsSpread: call.args.map(\.isSpread),
            argIsTrailingLambda: call.args.map(\.isTrailingLambda),
            signedIntegerLiterals: call.args.map(\.signedIntegerLiteral),
            unsignedIntegerLiterals: call.args.map(\.unsignedIntegerLiteral),
            explicitTypeArgs: call.explicitTypeArgs,
            expectedType: expectedType,
            elvisLhsExpectedTypeHint: call.elvisLhsExpectedTypeHint,
            elvisRhsCallResultTypeHint: call.elvisRhsCallResultTypeHint,
            implicitReceiverType: implicitReceiverType,
            dispatchReceiverTypes: call.dispatchReceiverTypes,
            boundObjectDispatchReceiverCandidates: call.boundObjectDispatchReceiverCandidates
        )
    }

    private(set) var scopeHits: Int = 0
    private(set) var scopeMisses: Int = 0
    private(set) var callResolutionHits: Int = 0
    private(set) var callResolutionMisses: Int = 0

    func recordCallResolutionHit() {
        callResolutionHits += 1
    }

    func recordCallResolutionMiss() {
        callResolutionMisses += 1
    }
}
