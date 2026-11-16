import Foundation

public protocol Scope: AnyObject {
    func lookup(_ name: InternedString) -> [SymbolID]
    /// Stops at the innermost scope containing matching bindings, so declarations
    /// in a different namespace do not shadow the requested candidates.
    func lookup(_ name: InternedString, matching predicate: (SymbolID) -> Bool) -> [SymbolID]
    /// Like `lookup`, but merges bindings from every scope in the parent chain
    /// instead of stopping at the innermost scope that binds `name`. Used as a
    /// resolution fallback to recover candidates that ordinary (shadowing)
    /// lookup hides — e.g. a `kotlin.text` String extension shadowed by a
    /// same-named extension declared in the current package.
    func lookupMergingChain(_ name: InternedString) -> [SymbolID]
    /// Classifier-namespace lookup with Kotlin's import tier order. The
    /// physical chain places a file's package scope above its explicit-import
    /// scope. For the classifier namespace Kotlin instead ranks an explicit
    /// single-type or alias import above same-package declarations, while
    /// wildcard and default imports still rank below them, so this promotes
    /// the explicit-import tier ahead of the file/package tiers. Scopes
    /// nested inside the file scope (locals, member and type-parameter
    /// scopes) keep innermost priority. Returns the matching bindings of the
    /// winning tier only, like `lookup(_:matching:)`.
    func lookupClassifier(_ name: InternedString, matching predicate: (SymbolID) -> Bool) -> [SymbolID]
    func insert(_ sym: SymbolID)
}

open class BaseScope: Scope {
    public let parent: Scope?
    private let symbols: SymbolTable
    private var locals: [InternedString: [SymbolID]] = [:]
    // Tracks declarations kept outside the symbol lookup table, such as locals.
    private var localValueOrClassifierDeclarations: [InternedString: Set<ExprID>] = [:]

    public init(parent: Scope?, symbols: SymbolTable) {
        self.parent = parent
        self.symbols = symbols
    }

    /// Additional same-tier bindings supplied lazily by subclasses. Imported
    /// package members register on demand, so a package scope resolves its
    /// members from the symbol table instead of a pre-collected mapping.
    /// Inserted bindings keep priority so source declarations still precede
    /// imported ones in the merged candidate order.
    open func deferredCandidates(for name: InternedString) -> [SymbolID] {
        []
    }

    /// Whether this scope level registered a local value or classifier
    /// declaration for `name`. Those declarations live outside the symbol
    /// lookup table but still mark the lexical level that owns them.
    func declaresLocalValueOrClassifier(named name: InternedString) -> Bool {
        localValueOrClassifierDeclarations[name]?.isEmpty == false
    }

    /// Bound symbols plus lazily supplied same-tier candidates, deduplicated.
    func candidates(for name: InternedString) -> [SymbolID] {
        let bound = locals[name] ?? []
        let deferred = deferredCandidates(for: name)
        guard !deferred.isEmpty else { return bound }
        guard !bound.isEmpty else { return deferred }
        var merged = bound
        var seen = Set(bound)
        for symbol in deferred where seen.insert(symbol).inserted {
            merged.append(symbol)
        }
        return merged
    }

    open func lookup(_ name: InternedString) -> [SymbolID] {
        symbols.attribution?.increment(.scopeLookupVisits)
        return withAttributionTiming(.scopeLookup, attribution: symbols.attribution) {
            let local = candidates(for: name)
            if !local.isEmpty {
                return local
            }
            return parent?.lookup(name) ?? []
        }
    }

    open func lookup(_ name: InternedString, matching predicate: (SymbolID) -> Bool) -> [SymbolID] {
        symbols.attribution?.increment(.scopeLookupVisits)
        return withAttributionTiming(.scopeLookup, attribution: symbols.attribution) {
            let local = candidates(for: name).filter(predicate)
            if !local.isEmpty {
                return local
            }
            return parent?.lookup(name, matching: predicate) ?? []
        }
    }

    open func lookupMergingChain(_ name: InternedString) -> [SymbolID] {
        symbols.attribution?.increment(.scopeLookupVisits)
        return withAttributionTiming(.scopeLookup, attribution: symbols.attribution) {
            var result: [SymbolID] = []
            var seen: Set<SymbolID> = []
            var current: Scope? = self
            while let scope = current as? BaseScope {
                for sym in scope.candidates(for: name) where seen.insert(sym).inserted {
                    result.append(sym)
                }
                current = scope.parent
            }
            return result
        }
    }

    open func lookupClassifier(_ name: InternedString, matching predicate: (SymbolID) -> Bool) -> [SymbolID] {
        symbols.attribution?.increment(.scopeLookupVisits)
        return withAttributionTiming(.scopeLookup, attribution: symbols.attribution) {
            var current: BaseScope? = self
            var reachedFileScope = false
            var fileLevelMatches: [SymbolID] = []
            var builtinMatches: [SymbolID] = []
            var defaultImportMatches: [SymbolID] = []
            var starImportMatches: [SymbolID] = []
            while let scope = current {
                let matches = scope.candidates(for: name).filter(predicate)
                if !reachedFileScope && !(scope is FileScope) {
                    if !matches.isEmpty {
                        return matches
                    }
                } else {
                    reachedFileScope = true
                    if scope is ExplicitImportScope {
                        if !matches.isEmpty {
                            return matches
                        }
                    } else if let defaultImportScope = scope as? DefaultImportScope {
                        // Kotlin ranks its builtin types (kotlin.Function,
                        // the mapped kotlin.collections interfaces,
                        // primitives, ...) above user star imports, but
                        // ordinary default imports below them: under
                        // `import java.util.*`, `Iterator` still binds
                        // kotlin.collections.Iterator while `ArrayDeque`
                        // binds java.util.ArrayDeque (KUU-4509). Callables
                        // keep the plain order: star imports outrank
                        // implicit stdlib imports during overload
                        // resolution (KUU-4424).
                        if builtinMatches.isEmpty && defaultImportMatches.isEmpty {
                            for match in matches {
                                if defaultImportScope.isKotlinBuiltinClassifier(match) {
                                    builtinMatches.append(match)
                                } else {
                                    defaultImportMatches.append(match)
                                }
                            }
                        }
                    } else if scope is WildcardImportScope {
                        if starImportMatches.isEmpty {
                            starImportMatches = matches
                        }
                    } else if fileLevelMatches.isEmpty {
                        fileLevelMatches = matches
                    }
                }
                current = scope.parent as? BaseScope
            }
            if !fileLevelMatches.isEmpty {
                return fileLevelMatches
            }
            if !builtinMatches.isEmpty {
                return builtinMatches
            }
            if !starImportMatches.isEmpty {
                return starImportMatches
            }
            return defaultImportMatches
        }
    }

    /// Include shadowed outer parameters: they remain rigid in nested bodies.
    func lexicalTypeParameterSymbols() -> Set<SymbolID> {
        var result: Set<SymbolID> = []
        var current: Scope? = self
        while let scope = current as? BaseScope {
            for symbol in scope.locals.values.flatMap({ $0 })
                where scope.symbols.symbol(symbol)?.kind == .typeParameter {
                result.insert(symbol)
            }
            current = scope.parent
        }
        return result
    }

    open func insert(_ sym: SymbolID) {
        guard let symbol = symbols.symbol(sym) else {
            return
        }
        var bucket = locals[symbol.name, default: []]
        if !bucket.contains(sym) {
            bucket.append(sym)
        }
        locals[symbol.name] = bucket
    }

    func registerLocalValueOrClassifierDeclaration(
        named name: InternedString,
        expression: ExprID
    ) -> Bool {
        var declarations = localValueOrClassifierDeclarations[name, default: []]
        guard !declarations.contains(expression) else { return false }
        let isRedeclaration = !declarations.isEmpty
        declarations.insert(expression)
        localValueOrClassifierDeclarations[name] = declarations
        return isRedeclaration
    }

    open func insertWithAlias(_ sym: SymbolID, asName: InternedString) {
        var bucket = locals[asName, default: []]
        if !bucket.contains(sym) {
            bucket.append(sym)
        }
        locals[asName] = bucket
    }
}

final class FileScope: BaseScope {}
final class PackageScope: BaseScope {}
class ImportScope: BaseScope {}

/// Package-level members resolved on demand. Inserted bindings behave like
/// any `BaseScope` local; a name that misses additionally asks the symbol
/// table for `<package> + name`, which drains pending compact-index entries
/// for the queried name only. Each `(path, include)` pair reproduces one of
/// the filters the eager package mapping applied (default-import skips,
/// wildcard accessibility, same-file-private routing).
class PackageMembersScope: BaseScope {
    private var memberSources: [(path: [InternedString], include: (SymbolID) -> Bool)] = []
    private let symbols: SymbolTable
    private let sourceCandidates: (InternedString) -> [SymbolID]

    /// One memoized `deferredCandidates` answer: the binding-list version of
    /// every source FQ name read while producing it, plus the filtered and
    /// deduplicated result. A pending-index claim, `define`, or record
    /// mutation under a listed name bumps its version, so a match proves the
    /// memo still reflects the symbol table (KUU-4021).
    private struct DeferredResult {
        /// Index-aligned with `memberSources` at build time.
        let versions: [(fqName: [InternedString], version: Int)]
        let candidates: [SymbolID]
    }

    /// `name` → memoized deferred candidates. Guards with
    /// `deferredCacheLock`: the shared default-import scope is reached from
    /// per-file scope chains, which `sema-parallel` workers may traverse
    /// concurrently.
    private var deferredResults: [InternedString: DeferredResult] = [:]
    private let deferredCacheLock = NSLock()

    init(
        parent: Scope?,
        symbols: SymbolTable,
        packages: [(path: [InternedString], include: (SymbolID) -> Bool)] = [],
        sourceCandidates: @escaping (InternedString) -> [SymbolID] = { _ in [] }
    ) {
        self.symbols = symbols
        self.sourceCandidates = sourceCandidates
        super.init(parent: parent, symbols: symbols)
        memberSources = packages
    }

    /// Adds a package path whose members become visible through this scope.
    /// Wildcard imports append each imported path instead of eagerly
    /// inserting every member the package provides.
    func addPackage(_ path: [InternedString], include: @escaping (SymbolID) -> Bool) {
        deferredCacheLock.lock()
        memberSources.append((path: path, include: include))
        deferredResults.removeAll(keepingCapacity: true)
        deferredCacheLock.unlock()
    }

    /// Repeat lookups dominate the type-check hot path: the same names are
    /// resolved per call site, but the lazily materialized symbol table only
    /// changes under them when a claim, `define`, or record mutation bumps a
    /// binding-list version. Memoize the filtered result and revalidate the
    /// per-source versions instead of re-running `lookupAll` + the include
    /// filters on every query (KUU-4021).
    override func deferredCandidates(for name: InternedString) -> [SymbolID] {
        symbols.attribution?.increment(.packageScopeQueries)
        return withAttributionTiming(.deferredScopeCandidates, attribution: symbols.attribution) {
            deferredCacheLock.lock()
            let cached = deferredResults[name]
            let sourceCount = memberSources.count
            deferredCacheLock.unlock()
            if let cached,
               cached.versions.count == sourceCount,
               symbols.fqNameListVersionsMatch(cached.versions)
            {
                return cached.candidates
            }

            deferredCacheLock.lock()
            let sources = memberSources
            deferredCacheLock.unlock()
            var versions: [(fqName: [InternedString], version: Int)] = []
            versions.reserveCapacity(sources.count)
            // Keep the source declaration order ahead of symbol-table
            // candidates, as when source members were inserted into the scope.
            var result = sourceCandidates(name)
            var seen = Set(result)
            for source in sources {
                let fqName = source.path + [name]
                let read = symbols.lookupAllWithVersion(fqName: fqName)
                versions.append((fqName: fqName, version: read.version))
                for symbol in read.symbols
                where symbols.symbol(symbol)?.kind != .package
                    && source.include(symbol) && seen.insert(symbol).inserted {
                    result.append(symbol)
                }
            }
            deferredCacheLock.lock()
            // A source appended mid-computation is picked up by the next query —
            // count mismatches are never stored.
            if memberSources.count == sources.count {
                deferredResults[name] = DeferredResult(versions: versions, candidates: result)
            }
            deferredCacheLock.unlock()
            return result
        }
    }
}

/// The shared scope holding default-imported (`kotlin.*` and friends)
/// members. `lookupClassifier` splits this tier: Kotlin builtin types
/// outrank user star imports while ordinary default imports rank below
/// them (KUU-4509); the marker lets the lookup tell the tier apart from
/// the per-file wildcard and same-package `PackageMembersScope`s.
final class DefaultImportScope: PackageMembersScope {
    /// Whether a default-imported classifier is one of Kotlin's builtin
    /// types (the `KotlinBuiltIns` set: `kotlin.Function`, the mapped
    /// collection interfaces, primitives, ranges, ...). Populated once by
    /// `TypeCheckScopeBuilder`, which owns the interner the FQ names are
    /// interned with.
    var isKotlinBuiltinClassifier: (SymbolID) -> Bool = { _ in false }
}

/// The per-file scope holding `import foo.*` star-imported members.
final class WildcardImportScope: PackageMembersScope {}

/// The scope holding a file's single-type and alias imports. Kotlin ranks
/// this tier above same-package declarations for classifier lookup, so
/// `lookupClassifier` needs to tell it apart from wildcard/default scopes.
final class ExplicitImportScope: ImportScope {}

final class ClassMemberScope: BaseScope {
    private let ownerSymbol: SymbolID
    private let thisType: TypeID?
    private let memberLookupSymbols: SymbolTable

    /// One memoized `deferredCandidates` answer (KUU-4574): the dependency
    /// versions of every supertype-chain parent the walk visited, sampled
    /// after the walk, plus the filtered candidates. A child reparenting,
    /// supertype-edge, or visibility mutation under a visited parent bumps
    /// its version, so a match proves the memo still reflects the symbol
    /// table. The walk's own lazy drains and metadata loads all complete
    /// inside the walk, before the snapshot is taken; a walk whose own
    /// loads still move a visited parent's version is never stored.
    private struct DeferredResult {
        /// Post-walk versions of the visited parents, in walk order.
        let dependencies: [(parent: SymbolID, version: Int)]
        let candidates: [SymbolID]
    }

    /// `name` → memoized deferred candidates. Guards with
    /// `deferredCacheLock`, mirroring `PackageMembersScope`: a scope chain
    /// can be traversed concurrently when parallel workers share a table.
    private var deferredResults: [InternedString: DeferredResult] = [:]
    private let deferredCacheLock = NSLock()

    init(parent: Scope?, symbols: SymbolTable, ownerSymbol: SymbolID, thisType: TypeID?) {
        self.ownerSymbol = ownerSymbol
        self.thisType = thisType
        self.memberLookupSymbols = symbols
        super.init(parent: parent, symbols: symbols)
    }

    var receiverType: TypeID? {
        thisType
    }

    var owner: SymbolID {
        ownerSymbol
    }

    /// Classifiers declared on supertypes are visible by simple name inside
    /// the class body: `Sub.M` names `Outer.I` through `Sub`'s inherited
    /// member scope (KUU-3250). Only type-like kinds qualify so value
    /// lookups keep their existing candidate sets.
    ///
    /// Kotlin inherits nested classifiers through the superclass chain only:
    /// a nested classifier reachable solely via an interface supertype is
    /// unresolved by simple name (`Child : Contract` cannot name
    /// `Contract.Entry` as `Entry`), even when the interface sits behind a
    /// superclass in the chain. Interfaces therefore end the walk instead of
    /// being expanded (KUU-3637, KUU-3636).
    /// Repeat lookups dominated the type-check hot path: every name
    /// resolution reaching this scope re-walked the owner's supertype chain
    /// and sorted each visited parent's whole child set. Memoize the answer
    /// per name and revalidate the visited parents' dependency versions
    /// instead (KUU-4574).
    override func deferredCandidates(for name: InternedString) -> [SymbolID] {
        memberLookupSymbols.attribution?.increment(.memberScopeQueries)
        return withAttributionTiming(.deferredScopeCandidates, attribution: memberLookupSymbols.attribution) {
            deferredCacheLock.lock()
            let cached = deferredResults[name]
            deferredCacheLock.unlock()
            if let cached,
               memberLookupSymbols.memberScopeDependencyVersionsMatch(cached.dependencies)
            {
                return cached.candidates
            }

            var result: [SymbolID] = []
            var seen: Set<SymbolID> = [ownerSymbol]
            var queue = [ownerSymbol]
            // Version of each visited parent sampled before its scan. The
            // walk's lazy child drains and supertype materialization can
            // still mutate an already-scanned parent later in the walk, so
            // the memo is stored only when every parent's version survives
            // the whole walk unchanged; a drifting walk simply recomputes on
            // the next query, exactly as before (KUU-4574).
            var preScanVersions: [(parent: SymbolID, version: Int)] = []
            preScanVersions.reserveCapacity(4)
            var index = 0
            while index < queue.count {
                let current = queue[index]
                index += 1
                preScanVersions.append((
                    parent: current,
                    version: memberLookupSymbols.memberScopeDependencyVersion(of: current)
                ))
                for child in memberLookupSymbols.children(of: current, named: name) {
                    guard let info = memberLookupSymbols.symbol(child) else { continue }
                    // Private members are not inherited: a `private` nested
                    // classifier declared on a supertype is not a member of this
                    // scope and must not shadow an accessible same-named
                    // declaration from an outer lexical scope (KUU-3798). The
                    // owner's own private members remain visible.
                    guard current == ownerSymbol || info.visibility != .private else { continue }
                    switch info.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        if !result.contains(child) {
                            result.append(child)
                        }
                    default:
                        break
                    }
                }
                for superSymbol in memberLookupSymbols.directSupertypes(for: current)
                    where seen.insert(superSymbol).inserted {
                    guard memberLookupSymbols.symbol(superSymbol)?.kind == .class else { continue }
                    queue.append(superSymbol)
                }
            }

            // Sample after the walk: the walk's own lazy loads have finished
            // by now, so the snapshot covers every mutation the result
            // depends on. Zip with the pre-scan samples in walk order —
            // `queue` visits each parent exactly once, so both lists align.
            let postWalkVersions = memberLookupSymbols.memberScopeDependencyVersions(of: queue)
            let walkWasStable = zip(preScanVersions, postWalkVersions)
                .allSatisfy { $0.version == $1.version }
            if walkWasStable {
                deferredCacheLock.lock()
                deferredResults[name] = DeferredResult(
                    dependencies: postWalkVersions,
                    candidates: result
                )
                deferredCacheLock.unlock()
            }
            return result
        }
    }
}

final class FunctionScope: BaseScope {}
final class BlockScope: BaseScope {}
