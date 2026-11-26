import Foundation

final class TypeCheckAttribution {
    enum Counter: String, CaseIterable {
        case exprInferences
        case callSites
        case scopeLookupVisits
        case packageScopeQueries
        case memberScopeQueries
        case memberScopeCandidatesScanned
        case symbolTableLookups
        case indexDrainCalls
        case resolveCallAttempts
        case probeCallAttempts
        case candidatesEvaluated
        case viableCandidates
        case genericInstantiations
        case constraintSolves
        case constraintsSolved
        case subtypeChecks
    }

    enum TimedScope: String, CaseIterable {
        case scopeLookup
        case deferredScopeCandidates
        case resolveCall
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
          member-scope candidates scanned:   \(value(.memberScopeCandidatesScanned))
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

func withAttributionTiming<T>(
    _ scope: TypeCheckAttribution.TimedScope,
    attribution: TypeCheckAttribution?,
    _ body: () throws -> T
) rethrows -> T {
    guard let attribution else { return try body() }
    return try attribution.measure(scope, body)
}
