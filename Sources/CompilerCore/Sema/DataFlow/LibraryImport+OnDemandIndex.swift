import Foundation

extension DataFlowSemaPhase {
    /// One compact-indexed (v3) `.kklib` whose records register on demand
    /// instead of through an eager `registerShells` pass.
    ///
    /// `loadImportedLibrarySymbols` attaches one source per v3 artifact.
    /// SymbolTable query paths drain matching entries through this type's
    /// pending maps before reading their indexes, so a shell is defined only
    /// when a lookup can actually reach it. All maps key on the raw index
    /// strings (`Substring` slices of the decoded index, no copies); the
    /// `registerEntry` closure — owned by the import function so it shares
    /// that function's shadow/link state — builds the shell and restores the
    /// structural edges the removed eager post-pass established.
    final class IndexedLibrarySource: IndexedLibraryEntryProvider {
        /// Position on the library search path, matching the library-dir
        /// enumeration order.
        let importOrder: Int
        let isStdlibArtifact: Bool

        private let indexedFile: IndexedMetadataFile
        private let interner: StringInterner
        private let moduleFQN: InternedString?
        private weak var symbols: SymbolTable?
        /// Claims one index entry: builds the index shell, runs
        /// `appendImportedBinding`, and restores parents, companion edges,
        /// extension receivers, and link-name routing. The second parameter
        /// carries this source's nominal type-parameter signatures, which the
        /// record builder needs and which live here so the closure does not
        /// retain the provider (the symbol table already does).
        private let registerEntry: (Int, [String: String]) -> SymbolID?
        /// Index entries rejected by the import-time validation scan (e.g.
        /// callable arity outside the supported range). They behave as if
        /// the record were absent: not claimable, not counted, contributing
        /// no link names, member keys, or package prefixes.
        private let rejectedIndices: Set<Int>

        init(
            importOrder: Int,
            indexedFile: IndexedMetadataFile,
            interner: StringInterner,
            moduleFQN: InternedString?,
            isStdlibArtifact: Bool,
            symbols: SymbolTable,
            rejectedEntryIndices: Set<Int> = [],
            registerEntry: @escaping (Int, [String: String]) -> SymbolID?
        ) {
            self.importOrder = importOrder
            self.indexedFile = indexedFile
            self.interner = interner
            self.moduleFQN = moduleFQN
            self.isStdlibArtifact = isStdlibArtifact
            self.symbols = symbols
            self.rejectedIndices = rejectedEntryIndices
            self.claimed = rejectedEntryIndices
            self.registerEntry = registerEntry
        }

        // MARK: - Pending-entry maps

        /// Index kinds that never surface through declaration lookup: they
        /// encode part of an owner (parameters, backing state, locals) and
        /// are claimed only through owner-driven drains.
        private static let machineryKinds: Set<SymbolKind> = [
            .valueParameter, .typeParameter, .backingField, .local, .label,
        ]
        /// Kinds whose FQ-name prefixes can describe a package, mirroring the
        /// eager synthetic-package pass (STDLIB-SHARED-011).
        private static let packageOwnerKinds: Set<SymbolKind> = [
            .class, .interface, .object, .enumClass, .annotationClass,
            .typeAlias, .function, .property, .constructor,
        ]

        private var mapsBuilt = false
        /// Entries already registered through any drain path. The pending
        /// maps overlap (a member is claimable by FQ name, by parent, by
        /// short name, and by link name), so claims key on the entry index —
        /// `claim(index:)` is the single point that keeps registration
        /// once-only.
        private var claimed: Set<Int> = []
        /// Declarations claimable by exact FQ name (`lookupAll`/`define`).
        private var pendingByFQName: [Substring: [Int]] = [:]
        /// Entries claimable by declaring parent path, including extension
        /// records reparented to a nominal owner at that path
        /// (`children(ofFQName:)`).
        private var pendingChildren: [Substring: [Int]] = [:]
        /// Declaration-kind entries claimable by simple name
        /// (`lookupByShortName`); machinery records stay out of name lookup.
        private var pendingByShortName: [Substring: [Int]] = [:]
        /// External link names claimable without touching declaration lookup
        /// (inline-body callee resolution).
        private var pendingLinks: [Substring: LinkTarget] = [:]
        /// Type-parameter records keyed by their owner's owner path, for the
        /// BUG-KSP-1217 phantom-parameter recovery keyed on single-callable
        /// FQ names.
        private var pendingTypeParametersByGrandparent: [Substring: [Int]] = [:]
        /// Every FQ name present in the index, used by the constructor-parent
        /// package rule: `pkg.Type.<init>` must not turn `pkg.Type` into a
        /// package when `pkg.Type` itself is a declaration.
        private var entryFQNames: Set<Substring> = []
        /// Entries whose initializer stubs the module-init emission
        /// enumerates by owner symbol (objects, companion owners, enum
        /// classes). They cannot stay pending: an unreferenced entry would
        /// otherwise lose the init call the eager import emitted.
        private var initializerEntryIndices: [Int] = []
        /// Package prefixes the index contributes, with the constructor
        /// exclusion applied (eager `syntheticPackagePaths` parity).
        private var packagePrefixes: Set<Substring> = []
        /// The package set is immutable after map construction. Cache misses as
        /// well as matches so repeated class-scope lookups never rescan it.
        private var childPackagePrefixesByParent: [String: [[InternedString]]] = [:]
        /// Nominal type-parameter signatures by owner FQ name, populated the
        /// same way the removed eager pre-pass populated them.
        private(set) var nominalTypeParametersByFQName: [String: String] = [:]
        private var stdlibMemberKeysCache: Set<BundledMemberKey>?

        enum LinkTarget {
            case symbol(Int)
            case defaultStub(Int)
            case propertyGetter(Int)
        }

        private func render(_ fqName: [InternedString]) -> String {
            fqName.map { interner.resolve($0) }.joined(separator: ".")
        }

        /// Registers an unclaimed index entry exactly once. Returns the new
        /// symbol, or `nil` when the entry was already claimed or its record
        /// is shadowed/duplicate-merged into another library's symbol.
        @discardableResult
        private func claim(index: Int) -> SymbolID? {
            guard claimed.insert(index).inserted else { return nil }
            return registerEntry(index, nominalTypeParametersByFQName)
        }

        private func buildMapsIfNeeded() {
            guard !mapsBuilt else { return }
            mapsBuilt = true
            pendingByFQName.reserveCapacity(indexedFile.entries.count)
            entryFQNames.reserveCapacity(indexedFile.entries.count)
            nominalTypeParametersByFQName.reserveCapacity(indexedFile.entries.count / 8)
            /// FQ parents of constructor records whose package contribution
            /// waits for the declaration-occupancy check below.
            var constructorParents: Set<Substring> = []
            for (index, entry) in indexedFile.entries.enumerated() {
                guard let record = entry.compactRecord, !rejectedIndices.contains(index)
                else { continue }
                let fqName = Substring(record.fqName)
                pendingByFQName[fqName, default: []].append(index)
                entryFQNames.insert(fqName)
                let parent = record.fqName.lastIndex(of: ".").map { Substring(record.fqName[..<$0]) } ?? ""
                pendingChildren[parent, default: []].append(index)
                if !Self.machineryKinds.contains(record.kind) {
                    let short = record.fqName.lastIndex(of: ".").map { Substring(record.fqName[record.fqName.index(after: $0)...]) } ?? fqName
                    pendingByShortName[short, default: []].append(index)
                }
                if let receiver = record.receiverOwnerFQName, !receiver.isEmpty {
                    pendingChildren[Substring(receiver), default: []].append(index)
                }
                if let link = record.externalLinkName, !link.isEmpty {
                    pendingLinks[Substring(link)] = .symbol(index)
                }
                if let link = record.defaultStubExternalLinkName, !link.isEmpty {
                    pendingLinks[Substring(link)] = .defaultStub(index)
                }
                if let link = record.propertyGetterExternalLinkName, !link.isEmpty {
                    pendingLinks[Substring(link)] = .propertyGetter(index)
                }
                if record.kind == .typeParameter {
                    // `owner.$id.name`: recover the owner path by dropping the
                    // last two segments when the middle one is the `$` id.
                    var cursor = Substring(record.fqName)
                    if let dot = cursor.lastIndex(of: ".") {
                        cursor = cursor[..<dot]
                        if let dot = cursor.lastIndex(of: "."), cursor[cursor.index(after: dot)...].hasPrefix("$") {
                            pendingTypeParametersByGrandparent[Substring(cursor[..<dot]), default: []].append(index)
                        }
                    }
                }
                if let signature = entry.nominalTypeParametersSignature,
                   nominalTypeParametersByFQName[record.fqName] == nil
                {
                    nominalTypeParametersByFQName[record.fqName] = signature
                }
                if record.objectInitializerLinkName?.isEmpty == false
                    || record.companionInitializerLinkName?.isEmpty == false
                    || record.enumStaticInitLinkName?.isEmpty == false
                {
                    initializerEntryIndices.append(index)
                }
                if Self.packageOwnerKinds.contains(record.kind) {
                    var cursor = Substring(record.fqName)
                    var isDirectParent = true
                    while let dot = cursor.lastIndex(of: ".") {
                        let prefix = cursor[..<dot]
                        if record.kind == .constructor, isDirectParent {
                            constructorParents.insert(Substring(prefix))
                        } else {
                            packagePrefixes.insert(Substring(prefix))
                        }
                        isDirectParent = false
                        cursor = prefix
                    }
                }
            }
            // Constructor FQ names nest under their nominal owner. That owner
            // path only becomes a package when no declaration occupies it —
            // matching the eager `lookupAll(prefix).contains(non-package)`
            // check evaluated against the fully registered table.
            for parent in constructorParents where !entryFQNames.contains(parent) {
                packagePrefixes.insert(parent)
            }
        }

        // MARK: - IndexedLibraryEntryProvider

        func drainEntries(fqName: [InternedString], into symbols: SymbolTable) {
            buildMapsIfNeeded()
            guard let indexes = pendingByFQName.removeValue(forKey: Substring(render(fqName))) else { return }
            for index in indexes {
                claim(index: index)
            }
        }

        func drainChildren(parentFQName: [InternedString], into symbols: SymbolTable) {
            buildMapsIfNeeded()
            guard let indexes = pendingChildren.removeValue(forKey: Substring(render(parentFQName))) else { return }
            for index in indexes {
                claim(index: index)
            }
        }

        func drainEntries(shortName: InternedString, into symbols: SymbolTable) {
            buildMapsIfNeeded()
            guard let indexes = pendingByShortName.removeValue(forKey: Substring(interner.resolve(shortName))) else { return }
            for index in indexes {
                claim(index: index)
            }
        }

        /// Claims the initializer-bearing entries once, at import time. The
        /// module-init emission enumerates registered owner symbols to emit
        /// object/companion/enum init calls before `main`; an entry that
        /// never drains would silently lose that call, so this subset must
        /// register eagerly even though nothing references it.
        func claimInitializerEntries() {
            buildMapsIfNeeded()
            for index in initializerEntryIndices {
                claim(index: index)
            }
        }

        func containsEntriesNested(under fqName: [InternedString]) -> Bool {
            buildMapsIfNeeded()
            return packagePrefixes.contains(Substring(render(fqName)))
        }

        /// Package prefixes nested directly under `parentFQName` (no further
        /// segments), so a children drain can synthesize the same child
        /// package shells the eager pass registered.
        func packagePrefixes(under parentFQName: [InternedString]) -> [[InternedString]] {
            buildMapsIfNeeded()
            let parent = render(parentFQName)
            if let cached = childPackagePrefixesByParent[parent] { return cached }
            let prefix = parent + "."
            var result: [[InternedString]] = []
            for packagePrefix in packagePrefixes {
                guard packagePrefix.hasPrefix(prefix) else { continue }
                let remainder = packagePrefix.dropFirst(prefix.count)
                guard !remainder.isEmpty, !remainder.contains(".") else { continue }
                result.append(packagePrefix.split(separator: ".").map { interner.intern(String($0)) })
            }
            // `packagePrefixes` is a set; sort so claim order — and therefore
            // byFQName order — is deterministic.
            let sorted = result.sorted { render($0) < render($1) }
            childPackagePrefixesByParent[parent] = sorted
            return sorted
        }

        func packageModuleFQN(for fqName: [InternedString]) -> InternedString? {
            containsEntriesNested(under: fqName) ? moduleFQN : nil
        }

        func materializeAll(into symbols: SymbolTable) {
            buildMapsIfNeeded()
            for index in indexedFile.entries.indices {
                claim(index: index)
            }
            for prefix in packagePrefixes.sorted() {
                let fqName = prefix.split(separator: ".").map { interner.intern(String($0)) }
                _ = symbols.lookupAll(fqName: fqName)
            }
        }

        // MARK: - Import-phase resolvers

        /// Claims every entry at `fqName` by its raw index string — the
        /// resolver path has no interned segments to render.
        @discardableResult
        func claimEntries(fqNameString: String) -> Bool {
            buildMapsIfNeeded()
            guard let indexes = pendingByFQName.removeValue(forKey: Substring(fqNameString)) else { return false }
            for index in indexes {
                claim(index: index)
            }
            return true
        }

        /// Resolves a producer external link name, registering its entry if
        /// still pending. Getter links resolve through the property's
        /// synthesized accessor, which exists only once the property's own
        /// binding has been applied — the lazy materializer provides that.
        func resolveLinkName(_ name: String) -> SymbolID? {
            buildMapsIfNeeded()
            guard let target = pendingLinks.removeValue(forKey: Substring(name)),
                  let symbols
            else { return nil }
            switch target {
            case let .symbol(index):
                return claim(index: index)
            case let .defaultStub(index):
                return claim(index: index).map(SyntheticSymbolScheme.defaultStubSymbol)
            case let .propertyGetter(index):
                guard let property = claim(index: index) else {
                    // Already registered through another drain; the apply-time
                    // hook in the lazy loader owns the link map entry.
                    return nil
                }
                symbols.ensureLazyImportedMetadataLoaded(for: property)
                return symbols.extensionPropertyGetterAccessor(for: property)
            }
        }

        /// Function/constructor entries at `fqName` that no drain has claimed
        /// yet. The phantom-parameter single-owner rule combines this with
        /// the already-registered binding count.
        func pendingCallableCount(fqName: [InternedString]) -> Int {
            buildMapsIfNeeded()
            guard let indexes = pendingByFQName[Substring(render(fqName))] else { return 0 }
            return indexes.reduce(0) { count, index in
                guard !claimed.contains(index),
                      let kind = indexedFile.entries[index].compactRecord?.kind,
                      kind == .function || kind == .constructor
                else { return count }
                return count + 1
            }
        }

        /// Claims this index's type-parameter records owned under `fqName`,
        /// returning their freshly registered symbols.
        func claimTypeParameterSymbols(forOwner fqName: [InternedString]) -> [SymbolID] {
            buildMapsIfNeeded()
            guard let indexes = pendingTypeParametersByGrandparent.removeValue(forKey: Substring(render(fqName))) else { return [] }
            return indexes.compactMap { claim(index: $0) }
        }

        /// Member keys for the bundled-stdib merge, built straight from the
        /// index so no shell (let alone signature) is needed for entries the
        /// compilation never references.
        func memberKeys() -> Set<BundledMemberKey> {
            buildMapsIfNeeded()
            if let cached = stdlibMemberKeysCache { return cached }
            var keys: Set<BundledMemberKey> = []
            keys.reserveCapacity(indexedFile.entries.count)
            for (index, entry) in indexedFile.entries.enumerated() {
                guard let record = entry.compactRecord, !rejectedIndices.contains(index)
                else { continue }
                let arity: Int
                switch record.kind {
                case .function, .constructor:
                    arity = record.arity
                case .property, .field:
                    arity = 0
                default:
                    continue
                }
                let ownerString = record.receiverOwnerFQName.flatMap { $0.isEmpty ? nil : $0 }
                    ?? record.fqName.lastIndex(of: ".").map { String(record.fqName[..<$0]) } ?? ""
                let nameString = record.fqName.lastIndex(of: ".").map { String(record.fqName[record.fqName.index(after: $0)...]) } ?? record.fqName
                let owner = ownerString.isEmpty
                    ? []
                    : ownerString.split(separator: ".").map { interner.intern(String($0)) }
                keys.insert(BundledMemberKey(
                    ownerFQName: owner,
                    name: interner.intern(nameString),
                    arity: arity
                ))
            }
            stdlibMemberKeysCache = keys
            return keys
        }
    }
}
