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
        let local = candidates(for: name)
        if !local.isEmpty {
            return local
        }
        return parent?.lookup(name) ?? []
    }

    open func lookup(_ name: InternedString, matching predicate: (SymbolID) -> Bool) -> [SymbolID] {
        let local = candidates(for: name).filter(predicate)
        if !local.isEmpty {
            return local
        }
        return parent?.lookup(name, matching: predicate) ?? []
    }

    open func lookupMergingChain(_ name: InternedString) -> [SymbolID] {
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

    open func lookupClassifier(_ name: InternedString, matching predicate: (SymbolID) -> Bool) -> [SymbolID] {
        var current: BaseScope? = self
        var reachedFileScope = false
        var fileLevelMatches: [SymbolID] = []
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
                } else if fileLevelMatches.isEmpty {
                    fileLevelMatches = matches
                }
            }
            current = scope.parent as? BaseScope
        }
        return fileLevelMatches
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
final class PackageMembersScope: BaseScope {
    private var memberSources: [(path: [InternedString], include: (SymbolID) -> Bool)] = []
    private let symbols: SymbolTable

    init(
        parent: Scope?,
        symbols: SymbolTable,
        packages: [(path: [InternedString], include: (SymbolID) -> Bool)] = []
    ) {
        self.symbols = symbols
        super.init(parent: parent, symbols: symbols)
        memberSources = packages
    }

    /// Adds a package path whose members become visible through this scope.
    /// Wildcard imports append each imported path instead of eagerly
    /// inserting every member the package provides.
    func addPackage(_ path: [InternedString], include: @escaping (SymbolID) -> Bool) {
        memberSources.append((path: path, include: include))
    }

    override func deferredCandidates(for name: InternedString) -> [SymbolID] {
        var result: [SymbolID] = []
        var seen: Set<SymbolID> = []
        for source in memberSources {
            for symbol in symbols.lookupAll(fqName: source.path + [name])
            where symbols.symbol(symbol)?.kind != .package
                && source.include(symbol) && seen.insert(symbol).inserted {
                result.append(symbol)
            }
        }
        return result
    }
}
/// The scope holding a file's single-type and alias imports. Kotlin ranks
/// this tier above same-package declarations for classifier lookup, so
/// `lookupClassifier` needs to tell it apart from wildcard/default scopes.
final class ExplicitImportScope: ImportScope {}

final class ClassMemberScope: BaseScope {
    private let ownerSymbol: SymbolID
    private let thisType: TypeID?
    private let memberLookupSymbols: SymbolTable

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
    override func deferredCandidates(for name: InternedString) -> [SymbolID] {
        var result: [SymbolID] = []
        var seen: Set<SymbolID> = [ownerSymbol]
        var queue = [ownerSymbol]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            for child in memberLookupSymbols.children(of: current) {
                guard let info = memberLookupSymbols.symbol(child), info.name == name else { continue }
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
        return result
    }
}

final class FunctionScope: BaseScope {}
final class BlockScope: BaseScope {}
