import Foundation

/// Per-declaration hashes used to decide what a source change invalidates.
///
/// * `signatureHash` covers everything callers can observe (name, parameter and
///   return types, modifiers, type parameters, and — for `inline` declarations —
///   the body, because inlining copies it into callers).
/// * `bodyHash` covers the implementation only.
///
/// The hashes are produced by the front end from syntax, never from `SymbolID`
/// or arena indices, so they are stable across runs.
public struct DeclarationUnit: Equatable, Codable, Sendable {
    /// Fully qualified, overload-distinguishing identity (e.g. `pkg.foo(Int,String)`).
    public let id: String
    public let signatureHash: String
    public let bodyHash: String
    /// Identities of the declarations this one references.
    public let references: Set<String>

    public init(id: String, signatureHash: String, bodyHash: String, references: Set<String>) {
        self.id = id
        self.signatureHash = signatureHash
        self.bodyHash = bodyHash
        self.references = references
    }
}

/// Declaration-granularity counterpart of `DependencyGraph`.
public struct DeclarationDependencyGraph: Equatable, Codable, Sendable {
    public private(set) var units: [String: DeclarationUnit]

    public init(units: [DeclarationUnit] = []) {
        var map: [String: DeclarationUnit] = [:]
        for unit in units { map[unit.id] = unit }
        self.units = map
    }

    /// Declarations that must be recompiled when going from `previous` to `self`.
    ///
    /// * new or body-only changes invalidate just that declaration;
    /// * a signature change (or removal) additionally invalidates its direct
    ///   dependents. Further propagation is not needed: dependents' own
    ///   signature hashes are recomputed from the new sources, so if a
    ///   dependent's observable signature changed it appears here itself and
    ///   brings its own dependents along.
    /// * references that cannot be resolved to a known declaration are ignored.
    public func invalidated(since previous: DeclarationDependencyGraph) -> Set<String> {
        var dependents: [String: Set<String>] = [:]
        for unit in units.values {
            for reference in unit.references { dependents[reference, default: []].insert(unit.id) }
        }
        // A dependent's *previous* references also matter: a declaration that
        // used to call a removed function must be rebuilt (and now fail Sema).
        var previousDependents: [String: Set<String>] = [:]
        for unit in previous.units.values {
            for reference in unit.references { previousDependents[reference, default: []].insert(unit.id) }
        }

        var result = Set<String>()
        for (id, unit) in units {
            guard let old = previous.units[id] else {
                result.insert(id)
                continue
            }
            if old.bodyHash != unit.bodyHash || old.references != unit.references {
                result.insert(id)
            }
            if old.signatureHash != unit.signatureHash {
                result.insert(id)
                result.formUnion(dependents[id] ?? [])
                result.formUnion(previousDependents[id] ?? [])
            }
        }
        for id in previous.units.keys where units[id] == nil {
            result.formUnion(previousDependents[id] ?? [])
        }
        return result.filter { units[$0] != nil }
    }

    /// Content-address for one declaration's compiled output. Depends on the
    /// declaration's own hashes, the *signatures* (not bodies) of everything it
    /// references, and an `environment` hash covering compiler build, options
    /// and the stdlib artifact — so a body edit elsewhere never changes it.
    public func cacheKey(for id: String, environment: String) -> String? {
        guard let unit = units[id] else { return nil }
        var parts = ["decl-v1", environment, unit.id, unit.signatureHash, unit.bodyHash]
        for reference in unit.references.sorted() {
            // Unknown references (stdlib, externals) are pinned by `environment`.
            parts.append("\(reference)=\(units[reference]?.signatureHash ?? "external")")
        }
        return ContentAddressedStore.makeKey(parts: parts)
    }
}
