import Foundation

/// Counters and inclusive timers attributing `type-check` cost to its hot
/// paths (KUU-3779).
///
/// ``TypeCheckSemaPhase`` installs one collector on the compilation's
/// ``TypeSystem`` and ``SymbolTable`` for the duration of the `type-check`
/// sub-phase — only when `time-phases` installed a ``PhaseTimer`` — and the
/// driver prints the totals after the phase-timing summary. Instrumentation
/// points reduce to an optional load when no collector is installed, so
/// ordinary compiles pay nothing.
///
/// Mutations funnel through a lock because `sema-parallel` body workers can
/// share one collector; a timer scope already active on another worker is
/// skipped rather than re-timed, keeping each bucket outermost-only under
/// recursion (nested work attributes to the enclosing scope, matching how
/// `imports.lazyMaterialize` accumulates).
final class TypeCheckAttribution {
    enum Counter: String, CaseIterable {
        /// `TypeCheckDriver.inferExpr` visits, including re-inference.
        case exprInferences
        /// `inferCallExpr` / `inferMemberCallImpl` entries.
        case callSites
        /// `Scope.lookup`-family calls, counted once per chain level visited.
        case scopeLookupVisits
        /// `PackageMembersScope.deferredCandidates` invocations — each scans
        /// the fqName index once per visible package source.
        case packageScopeQueries
        /// `ClassMemberScope.deferredCandidates` invocations — each walks the
        /// owner's supertype chain scanning children by name.
        case memberScopeQueries
        /// `children(of:)` entries scanned inside member-scope queries.
        case memberScopeChildrenScanned
        /// `SymbolTable.lookupAll` / `lookupByShortName` calls.
        case symbolTableLookups
        /// Compact-index drains demanded by the above lookups.
        case indexDrainCalls
        /// `OverloadResolver.resolveCall` invocations.
        case resolveCallAttempts
        /// `OverloadResolver.probeCall` invocations.
        case probeCallAttempts
        /// Per-candidate evaluations across all resolution attempts.
        case candidatesEvaluated
        /// Candidates surviving constraint solving.
        case viableCandidates
        /// Non-empty fresh type-variable environments created by
        /// `TypeSystem.makeTypeVarBySymbol` — one per generic instantiation.
        case genericInstantiations
        /// `ConstraintSolver.solve` invocations.
        case constraintSolves
        /// Total variable constraints fed to the solver.
        case constraintsSolved
        /// `TypeSystem.isSubtype` judgments.
        case subtypeChecks
    }

    enum TimedScope: String, CaseIterable {
        /// Scope-chain name lookup, inside or outside overload resolution.
        case scopeLookup
        /// On-demand candidate production (package index drains and member
        /// hierarchy scans) — a sub-bucket of `scopeLookup`.
        case deferredScopeCandidates
        /// `resolveCall` / `probeCall`, including nested candidate work.
        case resolveCall
        /// `ConstraintSolver.solve`.
        case constraintSolve
    }

    private let lock = NSLock()
    private var counters: [Counter: Int] = [:]
    private var accumulatedNanos: [TimedScope: UInt64] = [:]
    private var activeScopes: Set<TimedScope> = []

    func increment(_ counter: Counter, by delta: Int = 1) {
        lock.lock()
        counters[counter, default: 0] += delta
        lock.unlock()
    }

    /// Adds the body's wall-clock duration to `scope`. When the same scope is
    /// already active on this collector the body runs untimed, so recursive
    /// re-entry (e.g. `resolveCall` reached through lambda-body inference)
    /// attributes its time to the outermost invocation.
    func measure<T>(_ scope: TimedScope, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        let inserted = activeScopes.insert(scope).inserted
        lock.unlock()
        guard inserted else { return try body() }
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let end = DispatchTime.now().uptimeNanoseconds
            lock.lock()
            activeScopes.remove(scope)
            accumulatedNanos[scope, default: 0] += end - start
            lock.unlock()
        }
        return try body()
    }

    func value(_ counter: Counter) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counters[counter] ?? 0
    }

    func nanos(_ scope: TimedScope) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return accumulatedNanos[scope] ?? 0
    }

    /// Standalone report printed after `PhaseTimer`'s summary. Buckets are
    /// inclusive and overlap: `deferredScopeCandidates` nests inside
    /// `scopeLookup`, and `constraintSolve` nests inside `resolveCall`.
    func summary() -> String {
        func ms(_ scope: TimedScope) -> String {
            String(format: "%.2f", Double(nanos(scope)) / 1_000_000.0)
        }
        let attempts = value(.resolveCallAttempts) + value(.probeCallAttempts)
        let evaluated = value(.candidatesEvaluated)
        let averageCandidates = attempts > 0
            ? String(format: "%.1f", Double(evaluated) / Double(attempts))
            : "-"
        return """
        ===== Type-Check Attribution =====
        inferExpr visits:                    \(value(.exprInferences))
        call sites checked:                  \(value(.callSites))
        scope lookup visits:                 \(value(.scopeLookupVisits))
          package-scope queries:             \(value(.packageScopeQueries))
          member-scope queries:              \(value(.memberScopeQueries))
          member-scope children scanned:     \(value(.memberScopeChildrenScanned))
        symbol-table fqName lookups:         \(value(.symbolTableLookups))
          compact-index drains:              \(value(.indexDrainCalls))
        resolveCall / probeCall attempts:    \(value(.resolveCallAttempts)) / \(value(.probeCallAttempts))
        candidates evaluated:                \(evaluated) (avg \(averageCandidates)/attempt)
        viable candidates:                   \(value(.viableCandidates))
        generic instantiations:              \(value(.genericInstantiations))
        constraint solves:                   \(value(.constraintSolves)) (constraints: \(value(.constraintsSolved)))
        isSubtype checks:                    \(value(.subtypeChecks))
        --- inclusive ms (outermost scopes) ---
        scopeLookup:                         \(ms(.scopeLookup))
          deferredScopeCandidates:           \(ms(.deferredScopeCandidates))
        resolveCall:                         \(ms(.resolveCall))
        constraintSolve:                     \(ms(.constraintSolve))
        """ + "\n"
    }
}

/// Times `body` under `scope` when a collector is installed, mirroring
/// `withSubPhaseTiming`'s nil-timer short-circuit.
func withAttributionTiming<T>(
    _ scope: TypeCheckAttribution.TimedScope,
    attribution: TypeCheckAttribution?,
    _ body: () throws -> T
) rethrows -> T {
    guard let attribution else { return try body() }
    return try attribution.measure(scope, body)
}
