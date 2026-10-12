// swiftlint:disable file_length
import Foundation

extension SymbolTable {
    /// Whether `import <path>` contributes the declarations nested under that
    /// path to unqualified lookup. A path that resolves only to packages acts
    /// like a package import (the `import kotlin.collections` quirk), and a
    /// wildcard import (`import a.b.*`) always contributes. A non-wildcard
    /// import whose path also resolves to a declaration must not: a class may
    /// share its FQ name with a synthesised package record, so treating
    /// `import kotlin.coroutines.CoroutineContext` as a package import would
    /// leak the interface's members (Element, Key, ...) into bare-name
    /// resolution and shadow same-named user declarations (KUU-1205).
    public func importPathContributesMembers(_ path: [InternedString], isWildcard: Bool) -> Bool {
        let resolved = lookupAll(fqName: path)
        guard resolved.contains(where: { symbol($0)?.kind == .package }) else {
            return false
        }
        return isWildcard || resolved.allSatisfy { symbol($0)?.kind == .package }
    }

    /// Member extensions use [dispatch, extension, value arguments], while
    /// their semantic signature stores only the extension receiver.
    public func memberExtensionOwnerSymbol(for callee: SymbolID) -> SymbolID? {
        // Property accessors are parented by their property, not its owner.
        if let property = parentSymbol(for: callee),
           symbol(property)?.kind == .property,
           symbol(property)?.flags.contains(.memberExtension) == true,
           let owner = parentSymbol(for: property),
           let ownerInfo = symbol(owner),
           [.class, .interface, .enumClass, .object].contains(ownerInfo.kind)
        {
            return owner
        }
        // A member-extension *property* itself (e.g. `val String.cstr` declared
        // on MemScope) has its dispatch owner as its direct parent.
        if symbol(callee)?.kind == .property,
           symbol(callee)?.flags.contains(.memberExtension) == true,
           let owner = parentSymbol(for: callee),
           let ownerInfo = symbol(owner),
           [.class, .interface, .enumClass, .object].contains(ownerInfo.kind)
        {
            return owner
        }
        guard let signature = functionSignature(for: callee),
              signature.receiverType != nil,
              symbol(callee)?.flags.contains(.memberExtension) == true,
              let owner = parentSymbol(for: callee),
              let ownerInfo = symbol(owner),
              [.class, .interface, .enumClass, .object].contains(ownerInfo.kind),
              symbol(callee)?.flags.contains(.extensionMemberAlias) != true
        else { return nil }
        return owner
    }
}

/// Compact member shape recovered from a v2 metadata index entry when an
/// imported symbol is registered as a lazy shell. Arity-based member keys
/// (bundled-overlap checks) can be answered from this shape without
/// materializing the declaration body.
struct ImportedMemberIndexShape {
    let arity: Int
    let receiverOwnerFQName: [InternedString]?
}

public final class SymbolTable {
    private var symbolsStorage: [SemanticSymbol] = []
    private var byFQName: [[InternedString]: [SymbolID]] = [:]
    private var byShortName: [InternedString: [SymbolID]] = [:]
    private var byKind: [SymbolKind: [SymbolID]] = [:]
    private var byParentFQName: [[InternedString]: [SymbolID]] = [:]
    private var byDeclSite: [SourceRange: [SymbolID]] = [:]
    private var functionSignatures: [SymbolID: FunctionSignature] = [:]
    /// Owning function/constructor for each symbol listed in some signature's
    /// `valueParameterSymbols`; populated by `setFunctionSignature`. The first
    /// registrant wins: later signatures may copy a parameter list wholesale
    /// (e.g. synthesized forwarding helpers), but the parameter's semantic
    /// owner is the declaration it was defined on.
    private var valueParameterOwners: [SymbolID: SymbolID] = [:]
    private var propertyTypes: [SymbolID: TypeID] = [:]
    private var propertyHasCustomGetter: [SymbolID: Bool] = [:]
    private var directSupertypes: [SymbolID: [SymbolID]] = [:]
    /// Inverse of `directSupertypes`: supertype symbol → the nominal types
    /// that declare it. Kept in sync by `setDirectSupertypes` so
    /// `directSubtypes(of:)` reads a precomputed list instead of scanning
    /// every nominal type in the module on each call.
    private var directSubtypesIndex: [SymbolID: [SymbolID]] = [:]
    private var supertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]
    private var nominalLayouts: [SymbolID: NominalLayout] = [:]
    private var nominalLayoutHints: [SymbolID: NominalLayoutHint] = [:]
    private var externalLinkNames: [SymbolID: String] = [:]
    /// Backend ABI return type for functions whose compiled calling convention
    /// differs from their source-level return type (e.g. raw `Int` string handles).
    private var functionABIReturnTypes: [SymbolID: TypeID] = [:]
    private var stdlibSpecialCallKindsBySymbol: [SymbolID: StdlibSpecialCallKind] = [:]
    private var typeAliasUnderlyingTypes: [SymbolID: TypeID] = [:]
    private var typeAliasTypeParameters: [SymbolID: [SymbolID]] = [:]
    private var parentSymbols: [SymbolID: SymbolID] = [:]
    private var backingFieldSymbols: [SymbolID: SymbolID] = [:]
    private var delegateStorageSymbols: [SymbolID: SymbolID] = [:]
    private var delegateGetValueSymbols: [SymbolID: SymbolID] = [:]
    private var delegateSetValueSymbols: [SymbolID: SymbolID] = [:]
    private var delegateProvideDelegateSymbols: [SymbolID: SymbolID] = [:]
    private var accessorOwnerProperties: [SymbolID: SymbolID] = [:]
    private var extensionPropertyReceiverTypes: [SymbolID: TypeID] = [:]
    private var declaredExtensionProperties: Set<SymbolID> = []
    private var extensionPropertyGetterAccessors: [SymbolID: SymbolID] = [:]
    private var extensionPropertySetterAccessors: [SymbolID: SymbolID] = [:]
    private var typeParameterUpperBoundsMap: [SymbolID: [TypeID]] = [:]
    private var pendingTypeParameterBoundConflictChecks: [(symbol: SymbolID, declSite: SourceRange?)] = []
    private var sourceFileIDs: [SymbolID: FileID] = [:]
    private var moduleFQNames: [SymbolID: InternedString] = [:]
    private var annotationsStorage: [SymbolID: [MetadataAnnotationRecord]] = [:]
    private var companionObjectSymbols: [SymbolID: SymbolID] = [:]
    /// BUG-inner-outer: the synthetic `$outer` field holding an `inner
    /// class`'s enclosing-instance link, keyed by the inner class's own
    /// symbol. `nil` for every non-inner nominal.
    private var outerInstanceFieldSymbols: [SymbolID: SymbolID] = [:]
    private var objectInitializerSymbols: [SymbolID: SymbolID] = [:]
    private var objectLazyInitializerSymbols: [SymbolID: SymbolID] = [:]
    private var companionObjectInitializerSymbols: [SymbolID: SymbolID] = [:]
    private var enumStaticInitSymbols: [SymbolID: SymbolID] = [:]
    private var enumEntryDispatchTargets: [SymbolID: [EnumEntryDispatchTarget]] = [:]
    private var enumEntryDispatchBaseSymbols: [SymbolID: SymbolID] = [:]
    private var valueClassUnderlyingTypes: [SymbolID: TypeID] = [:]
    private var sealedSubclassesStorage: [SymbolID: [SymbolID]] = [:]
    private var constValueExprKinds: [SymbolID: KIRExprKind] = [:]
    private var delegateHasProvideDelegate: Set<SymbolID> = []
    private var expectActualLinks: [SymbolID: SymbolID] = [:]
    private var contractNonNullEffects: [SymbolID: ContractNonNullEffect] = [:]
    private var contractImplicationEffects: [SymbolID: [ContractImplicationEffect]] = [:]
    private var contractReturnsEffects: [SymbolID: ContractReturnsEffect] = [:]
    private var contractCallsInPlaceEffects: [SymbolID: [ContractCallsInPlaceEffect]] = [:]
    private var contractReturnsNotNullEffects: Set<SymbolID> = []
    private var contractConditionEffects: [SymbolID: ContractConditionEffect] = [:]
    /// ARCH-029: imported library declarations are registered from a compact
    /// metadata index and materialized the first time semantic data is queried.
    private var lazyImportedMetadataLoader: ((SymbolID) -> Void)?
    private var lazyImportedMetadataLoaded: Set<SymbolID> = []
    private var lazyImportedMetadataLoadInProgress: Set<SymbolID> = []
    /// Index-shape hints for lazy shells, keyed by symbol. Consulted by
    /// arity-key builders so they never force body materialization.
    private var importedMemberIndexShapes: [SymbolID: ImportedMemberIndexShape] = [:]
    /// CLASS-008: Interfaces delegated by a class via `: Interface by expr`.
    /// Key = class symbol, Value = set of interface symbols that class delegates to.
    private var delegatedInterfacesByClass: [SymbolID: Set<SymbolID>] = [:]

    /// Globals that carry `.importedLibrary` but whose storage is defined by
    /// this compilation — `.klib` modules ship serialized IR without a
    /// precompiled object, so the backend must emit a real slot instead of
    /// an extern reference. Populated when KlibBodyLowerer materializes
    /// top-level fields, enum entries and object singletons.
    private var klibDefinedGlobalSymbols: Set<SymbolID> = []

    /// KUU-655: an `override` whose own declaration carries no default value
    /// expressions still accepts calls that omit the overridden parameter
    /// (Kotlin inherits the base's default). `OverrideDefaultArgumentInheritance`
    /// copies the base's `valueParameterHasDefaultValues` flags onto such an
    /// override's `FunctionSignature` so overload resolution accepts the
    /// call, and records the link here so KIR call-site lowering knows to
    /// route through the base's `$default` stub (the override itself never
    /// gets one -- its AST has no default expressions to evaluate).
    /// Key = override symbol, Value = the overridden symbol that actually
    /// owns the default value expressions (possibly several levels up an
    /// override chain).
    private var overrideDefaultsBaseSymbols: [SymbolID: SymbolID] = [:]

    /// Thread safety lock for concurrent access. Recursive because the lazy
    /// imported-metadata loader re-enters this table (`define`, `lookupAll`,
    /// `setFunctionSignature`, ...) while materializing a symbol, and that
    /// materialization can be triggered from inside `define`'s critical
    /// section (e.g. `canCoexistAsOverload` → `extensionPropertyReceiverType`).
    /// A plain NSLock would self-deadlock on that path.
    private let lock = NSRecursiveLock()

    public init() {}

    /// Installs the per-compilation loader used by indexed `.kklib` metadata.
    /// The loader is intentionally callback-based so the metadata reader stays
    /// outside the symbol model and can reuse the normal import application path.
    func setLazyImportedMetadataLoader(
        alreadyLoaded: Set<SymbolID> = [],
        _ loader: ((SymbolID) -> Void)?
    ) {
        lazyImportedMetadataLoader = loader
        lazyImportedMetadataLoaded = alreadyLoaded
        lazyImportedMetadataLoadInProgress.removeAll()
    }

    var hasLazyImportedMetadataLoader: Bool {
        lazyImportedMetadataLoader != nil
    }

    /// Records the compact index shape of a lazy shell so arity-based member
    /// keys resolve without materializing the declaration body.
    func setImportedMemberIndexShape(_ shape: ImportedMemberIndexShape, for symbol: SymbolID) {
        importedMemberIndexShapes[symbol] = shape
    }

    func importedMemberIndexShape(for symbol: SymbolID) -> ImportedMemberIndexShape? {
        importedMemberIndexShapes[symbol]
    }

    func ensureLazyImportedMetadataLoaded(for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        guard let loader = lazyImportedMetadataLoader,
              !lazyImportedMetadataLoaded.contains(symbol),
              !lazyImportedMetadataLoadInProgress.contains(symbol)
        else {
            return
        }
        lazyImportedMetadataLoadInProgress.insert(symbol)
        loader(symbol)
        lazyImportedMetadataLoadInProgress.remove(symbol)
        lazyImportedMetadataLoaded.insert(symbol)
    }

    public var count: Int {
        symbolsStorage.count
    }

    public func allSymbols() -> [SemanticSymbol] {
        symbolsStorage
    }

    public func symbol(_ id: SymbolID) -> SemanticSymbol? {
        let index = Int(id.rawValue)
        guard index >= 0, index < symbolsStorage.count else {
            return nil
        }
        return symbolsStorage[index]
    }

    public func insertFlags(_ flags: SymbolFlags, for symbol: SymbolID) {
        let index = Int(symbol.rawValue)
        guard index >= 0, index < symbolsStorage.count else {
            return
        }
        symbolsStorage[index].flags.formUnion(flags)
    }

    public func removeFlags(_ flags: SymbolFlags, for symbol: SymbolID) {
        let index = Int(symbol.rawValue)
        guard index >= 0, index < symbolsStorage.count else {
            return
        }
        symbolsStorage[index].flags.subtract(flags)
    }

    public func setDeclSite(_ declSite: SourceRange?, for symbol: SymbolID) {
        let index = Int(symbol.rawValue)
        guard index >= 0, index < symbolsStorage.count else {
            return
        }
        symbolsStorage[index].declSite = declSite
    }

    /// ARCH-031: declaration sites of the given symbols, deduplicated and
    /// sorted by source position so diagnostics rendering stays deterministic.
    public func sortedDeclSites(of symbols: [SymbolID]) -> [SourceRange] {
        var sites: [SourceRange] = []
        for symbol in symbols {
            guard let site = self.symbol(symbol)?.declSite,
                  !sites.contains(site)
            else {
                continue
            }
            sites.append(site)
        }
        return sites.sorted {
            ($0.start.file.rawValue, $0.start.offset, $0.end.offset)
                < ($1.start.file.rawValue, $1.start.offset, $1.end.offset)
        }
    }

    public func lookup(fqName: [InternedString]) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return byFQName[fqName]?.first
    }

    public func lookupAll(fqName: [InternedString]) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        return byFQName[fqName] ?? []
    }

    public func lookupByShortName(_ name: InternedString) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        return byShortName[name] ?? []
    }

    public func define(
        kind: SymbolKind,
        name: InternedString,
        fqName: [InternedString],
        declSite: SourceRange?,
        visibility: Visibility,
        flags: SymbolFlags = [],
        isExtensionProperty: Bool = false,
        topLevelFileID: FileID? = nil
    ) -> SymbolID {
        lock.lock()
        defer { lock.unlock() }

        if let existing = byFQName[fqName], !existing.isEmpty {
            // File-private callables in other files do not occupy this declaration's scope.
            let existingSymbols = existing.compactMap { symbol($0) }.filter { existing in
                guard let topLevelFileID else { return true }
                return !canCoexistAsFilePrivateTopLevelCallable(
                    kind: kind, visibility: visibility, fileID: topLevelFileID, existing: existing
                )
            }

            let shouldCoexist = canCoexistAsOverload(
                kind: kind,
                existingSymbols: existingSymbols,
                isExtensionProperty: isExtensionProperty
            )
                || canCoexistAsExpectActual(kind: kind, flags: flags, existingSymbols: existingSymbols)
                || canCoexistAsSyntheticPropertyFamily(kind: kind, flags: flags, existingSymbols: existingSymbols)
            if shouldCoexist {
                let id = appendNewSymbol(
                    kind: kind,
                    name: name,
                    fqName: fqName,
                    declSite: declSite,
                    visibility: visibility,
                    flags: flags
                )
                if isExtensionProperty { declaredExtensionProperties.insert(id) }
                return id
            }
            // When a classifier coexists with a factory, a duplicate classifier
            // must reuse the classifier rather than the first (possibly callable) entry.
            if isNominalType(kind) || kind == .typeAlias,
               let matching = existingSymbols.first(where: { $0.kind == kind }) {
                return matching.id
            }
            return existingSymbols.first?.id ?? existing[0]
        }
        let id = appendNewSymbol(
            kind: kind,
            name: name,
            fqName: fqName,
            declSite: declSite,
            visibility: visibility,
            flags: flags
        )
        if isExtensionProperty { declaredExtensionProperties.insert(id) }
        return id
    }

    private func appendNewSymbol(
        kind: SymbolKind,
        name: InternedString,
        fqName: [InternedString],
        declSite: SourceRange?,
        visibility: Visibility,
        flags: SymbolFlags
    ) -> SymbolID {
        let id = SymbolID(rawValue: Int32(symbolsStorage.count))
        let symbol = SemanticSymbol(
            id: id,
            kind: kind,
            name: name,
            fqName: fqName,
            declSite: declSite,
            visibility: visibility,
            flags: flags
        )
        symbolsStorage.append(symbol)
        byFQName[fqName, default: []].append(id)
        byShortName[name, default: []].append(id)
        byKind[kind, default: []].append(id)
        if fqName.count >= 1 {
            let parentFQ = Array(fqName.dropLast())
            byParentFQName[parentFQ, default: []].append(id)
        }
        if let site = declSite {
            byDeclSite[site, default: []].append(id)
        }
        return id
    }

    /// Only top-level callables have distinct file facades; classifiers still
    /// occupy the package namespace even when declared private.
    func canCoexistAsFilePrivateTopLevelCallable(
        kind: SymbolKind,
        visibility: Visibility,
        fileID: FileID,
        existing: SemanticSymbol
    ) -> Bool {
        guard kind == .property || kind == .function,
              existing.kind == .property || existing.kind == .function,
              visibility == .private,
              existing.visibility == .private,
              parentSymbol(for: existing.id) == nil,
              let existingFile = sourceFileID(for: existing.id) ?? existing.declSite?.start.file
        else { return false }
        return existingFile != fileID
    }

    private func canCoexistAsOverload(
        kind: SymbolKind,
        existingSymbols: [SemanticSymbol],
        isExtensionProperty: Bool = false
    ) -> Bool {
        func isCallableLike(_ kind: SymbolKind) -> Bool {
            switch kind {
            case .function, .constructor:
                true
            default:
                false
            }
        }
        func isParameterLike(_ kind: SymbolKind) -> Bool {
            switch kind {
            case .valueParameter, .typeParameter:
                true
            default:
                false
            }
        }
        if kind == .package {
            return true
        }
        // Parameters are encoded as `ownerFQName + [paramName]`. A class and a
        // factory function that share an FQName (Kotlin `class Foo` + `fun Foo`)
        // therefore make class members and factory parameters collide in this
        // encoding — e.g. `AtomicIntArray.size` is both the residual property
        // and the `fun AtomicIntArray(size: Int, init: ...)` parameter. They
        // are distinct declarations and must coexist. Two parameters of the
        // same kind at one FQName still reuse the first symbol.
        if isParameterLike(kind) {
            return !existingSymbols.contains { $0.kind == kind }
        }
        let existingNonPackage = existingSymbols.filter { symbol in
            symbol.kind != .package && !isParameterLike(symbol.kind)
        }
        if existingNonPackage.isEmpty {
            return true
        }
        let existingNonPackageKinds = existingNonPackage.map(\.kind)
        if kind == .property {
            if isExtensionProperty {
                // Extension properties are disambiguated by receiver type at
                // call sites, the same way overloaded extension functions
                // are (e.g. `val Int.seconds` and `val Long.seconds`), so two
                // extension properties sharing a short name may coexist as
                // separate symbols. A non-extension property at the same FQ
                // name is still a genuine clash: it has no receiver to
                // disambiguate by. Mirrors the diagnostic-level check in
                // HeaderHelpers.hasDeclarationConflict.
                return existingNonPackage.allSatisfy { existing in
                    isCallableLike(existing.kind)
                        || (existing.kind == .property && (existing.flags.contains(.synthetic) || hasExtensionPropertyReceiver(existing.id)))
                }
            }
            return existingNonPackageKinds.allSatisfy { isCallableLike($0) }
        }
        if isCallableLike(kind) {
            // Allow functions/constructors to coexist with nominal types and
            // type aliases; Kotlin supports factory functions with the same
            // name as a type surface (e.g. AutoCloseable { ... }).
            // Kotlin also permits callable declarations to share a name with a
            // property, such as `var port` and `fun port(value: Int)`.
            return existingNonPackageKinds.allSatisfy {
                isCallableLike($0) || isNominalType($0) || $0 == .typeAlias || $0 == .property
            }
        }
        // Classifiers and factory functions must coexist in either registration order.
        if isNominalType(kind) || kind == .typeAlias {
            return existingNonPackageKinds.allSatisfy { isCallableLike($0) }
        }
        guard isOverloadable(kind) else {
            return false
        }
        return existingNonPackageKinds.allSatisfy { isOverloadable($0) }
    }

    private func canCoexistAsExpectActual(
        kind: SymbolKind,
        flags: SymbolFlags,
        existingSymbols: [SemanticSymbol]
    ) -> Bool {
        // Allow exactly one matching `expect`/`actual` partner at a given FQ name.
        let existingNonPackage = existingSymbols.filter {
            $0.kind != .package && !$0.flags.contains(.synthetic)
        }
        if (flags.contains(.expectDeclaration) || flags.contains(.actualDeclaration))
            && existingNonPackage.isEmpty
        {
            return true
        }
        guard existingNonPackage.count == 1, let existing = existingNonPackage.first else {
            return false
        }
        return isCompatibleExpectActualPair(newKind: kind, newFlags: flags, existing: existing)
    }

    private func canCoexistAsSyntheticPropertyFamily(
        kind: SymbolKind,
        flags: SymbolFlags,
        existingSymbols: [SemanticSymbol]
    ) -> Bool {
        guard kind == .property else {
            return false
        }
        let existingNonPackageSymbols = existingSymbols.filter { $0.kind != .package }
        guard !existingNonPackageSymbols.isEmpty else {
            return false
        }
        if !flags.contains(.synthetic) {
            return existingNonPackageSymbols.allSatisfy {
                $0.kind == .property && $0.flags.contains(.synthetic)
            }
        }
        return existingNonPackageSymbols.allSatisfy { symbol in
            switch symbol.kind {
            case .property:
                return symbol.flags.contains(.synthetic)
            // A source-backed factory can share a FQName with its nominal
            // return type, so its parameter may collide with a residual
            // synthetic property on that type (for example `size`).
            case .function, .constructor, .valueParameter, .typeParameter:
                return true
            default:
                return false
            }
        }
    }

    private func isOverloadable(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
    }

    private func isNominalType(_ kind: SymbolKind) -> Bool {
        kind == .class || kind == .enumClass || kind == .interface
    }

    public func setFunctionSignature(_ signature: FunctionSignature, for symbol: SymbolID) {
        functionSignatures[symbol] = signature
        for parameterSymbol in signature.valueParameterSymbols {
            if valueParameterOwners[parameterSymbol] == nil {
                valueParameterOwners[parameterSymbol] = symbol
            }
        }
    }

    /// The function/constructor whose signature lists `symbol` in
    /// `valueParameterSymbols`, if any signature has done so.
    public func valueParameterOwner(for symbol: SymbolID) -> SymbolID? {
        valueParameterOwners[symbol]
    }

    public func functionSignature(for symbol: SymbolID) -> FunctionSignature? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return functionSignatures[symbol]
    }

    /// KUU-655: see `overrideDefaultsBaseSymbols` above.
    public func setOverrideDefaultsBaseSymbol(_ base: SymbolID, for symbol: SymbolID) {
        overrideDefaultsBaseSymbols[symbol] = base
    }

    public func overrideDefaultsBaseSymbol(for symbol: SymbolID) -> SymbolID? {
        overrideDefaultsBaseSymbols[symbol]
    }

    public func setEnumEntryDispatchTargets(
        _ targets: [EnumEntryDispatchTarget],
        for dispatchSymbol: SymbolID
    ) {
        enumEntryDispatchTargets[dispatchSymbol] = targets
    }

    public func enumEntryDispatchTargets(for dispatchSymbol: SymbolID) -> [EnumEntryDispatchTarget] {
        enumEntryDispatchTargets[dispatchSymbol] ?? []
    }

    public func setEnumEntryDispatchBaseSymbol(_ baseSymbol: SymbolID, for dispatchSymbol: SymbolID) {
        enumEntryDispatchBaseSymbols[dispatchSymbol] = baseSymbol
    }

    public func enumEntryDispatchBaseSymbol(for dispatchSymbol: SymbolID) -> SymbolID? {
        enumEntryDispatchBaseSymbols[dispatchSymbol]
    }


    public func setPropertyType(_ type: TypeID, for symbol: SymbolID) {
        propertyTypes[symbol] = type
    }

    public func propertyType(for symbol: SymbolID) -> TypeID? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return propertyTypes[symbol]
    }

    /// The property a synthetic getter/setter accessor symbol encodes, or nil
    /// when `symbol` is a real member rather than a property accessor.
    public func propertySymbol(forAccessor accessor: SymbolID) -> SymbolID? {
        SyntheticSymbolScheme.decodedPropertyAccessor(accessor)?.property
    }

    public func setPropertyHasCustomGetter(_ value: Bool, for symbol: SymbolID) {
        propertyHasCustomGetter[symbol] = value
    }

    public func propertyHasCustomGetter(for symbol: SymbolID) -> Bool {
        propertyHasCustomGetter[symbol] ?? false
    }

    public func setDirectSupertypes(_ supertypes: [SymbolID], for symbol: SymbolID) {
        if let previous = directSupertypes[symbol] {
            for removedSupertype in previous where !supertypes.contains(removedSupertype) {
                directSubtypesIndex[removedSupertype]?.removeAll { $0 == symbol }
            }
        }
        directSupertypes[symbol] = supertypes
        var seen: Set<SymbolID> = []
        for supertype in supertypes where seen.insert(supertype).inserted {
            if directSubtypesIndex[supertype]?.contains(symbol) != true {
                directSubtypesIndex[supertype, default: []].append(symbol)
            }
        }
    }

    public func directSupertypes(for symbol: SymbolID) -> [SymbolID] {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return directSupertypes[symbol] ?? []
    }

    public func setSupertypeTypeArgs(_ args: [TypeArg], for child: SymbolID, supertype parent: SymbolID) {
        supertypeTypeArgsMap[child, default: [:]][parent] = args
    }

    public func supertypeTypeArgs(for child: SymbolID, supertype parent: SymbolID) -> [TypeArg] {
        ensureLazyImportedMetadataLoaded(for: child)
        return supertypeTypeArgsMap[child]?[parent] ?? []
    }

    public func directSubtypes(of symbol: SymbolID) -> [SymbolID] {
        (directSubtypesIndex[symbol] ?? []).sorted(by: { $0.rawValue < $1.rawValue })
    }

    public func addDelegatedInterface(_ interfaceSymbol: SymbolID, forClass classSymbol: SymbolID) {
        delegatedInterfacesByClass[classSymbol, default: []].insert(interfaceSymbol)
    }

    public func delegatedInterfaces(forClass classSymbol: SymbolID) -> [SymbolID] {
        (delegatedInterfacesByClass[classSymbol] ?? []).sorted(by: { $0.rawValue < $1.rawValue })
    }

    private var classDelegationFieldByClassAndInterface: [SymbolID: [SymbolID: SymbolID]] = [:]

    public func setClassDelegationField(
        _ fieldSymbol: SymbolID, forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID
    ) {
        classDelegationFieldByClassAndInterface[classSymbol, default: [:]][interfaceSymbol] = fieldSymbol
    }

    public func classDelegationField(forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID) -> SymbolID? {
        classDelegationFieldByClassAndInterface[classSymbol]?[interfaceSymbol]
    }

    private var classDelegationExprByClassAndInterface: [SymbolID: [SymbolID: ExprID]] = [:]

    public func setClassDelegationExpr(
        _ exprID: ExprID, forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID
    ) {
        classDelegationExprByClassAndInterface[classSymbol, default: [:]][interfaceSymbol] = exprID
    }

    public func classDelegationExpr(forClass classSymbol: SymbolID, interface interfaceSymbol: SymbolID) -> ExprID? {
        classDelegationExprByClassAndInterface[classSymbol]?[interfaceSymbol]
    }

    private var classDelegationForwardingMethodInfo: [SymbolID: (interfaceSymbol: SymbolID, interfaceMethodSymbol: SymbolID, fieldSymbol: SymbolID)] = [:]

    private var classDelegationForwardingMethodsByClass: [SymbolID: [SymbolID]] = [:]

    public func addClassDelegationForwardingMethod(
        _ forwardingSymbol: SymbolID,
        forClass classSymbol: SymbolID,
        interface interfaceSymbol: SymbolID,
        interfaceMethod interfaceMethodSymbol: SymbolID,
        field fieldSymbol: SymbolID
    ) {
        classDelegationForwardingMethodInfo[forwardingSymbol] = (interfaceSymbol, interfaceMethodSymbol, fieldSymbol)
        classDelegationForwardingMethodsByClass[classSymbol, default: []].append(forwardingSymbol)
    }

    public func classDelegationForwardingMethodSymbols(forClass classSymbol: SymbolID) -> [SymbolID] {
        classDelegationForwardingMethodsByClass[classSymbol] ?? []
    }

    public func classDelegationForwardingMethodInfo(for forwardingSymbol: SymbolID) -> (interfaceSymbol: SymbolID, interfaceMethodSymbol: SymbolID, fieldSymbol: SymbolID)? {
        classDelegationForwardingMethodInfo[forwardingSymbol]
    }

    private var classDelegationForwardingPropertyInfo: [SymbolID: (interfaceSymbol: SymbolID, interfacePropertySymbol: SymbolID, fieldSymbol: SymbolID)] = [:]

    private var classDelegationForwardingPropertiesByClass: [SymbolID: [SymbolID]] = [:]

    public func addClassDelegationForwardingProperty(
        _ forwardingSymbol: SymbolID,
        forClass classSymbol: SymbolID,
        interface interfaceSymbol: SymbolID,
        interfaceProperty interfacePropertySymbol: SymbolID,
        field fieldSymbol: SymbolID
    ) {
        classDelegationForwardingPropertyInfo[forwardingSymbol] = (interfaceSymbol, interfacePropertySymbol, fieldSymbol)
        classDelegationForwardingPropertiesByClass[classSymbol, default: []].append(forwardingSymbol)
    }

    public func classDelegationForwardingPropertySymbols(forClass classSymbol: SymbolID) -> [SymbolID] {
        classDelegationForwardingPropertiesByClass[classSymbol] ?? []
    }

    public func classDelegationForwardingPropertyInfo(for forwardingSymbol: SymbolID) -> (interfaceSymbol: SymbolID, interfacePropertySymbol: SymbolID, fieldSymbol: SymbolID)? {
        classDelegationForwardingPropertyInfo[forwardingSymbol]
    }

    public func setNominalLayout(_ layout: NominalLayout, for symbol: SymbolID) {
        nominalLayouts[symbol] = layout
    }

    public func nominalLayout(for symbol: SymbolID) -> NominalLayout? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return nominalLayouts[symbol]
    }

    public func setNominalLayoutHint(_ hint: NominalLayoutHint, for symbol: SymbolID) {
        nominalLayoutHints[symbol] = hint
    }

    public func nominalLayoutHint(for symbol: SymbolID) -> NominalLayoutHint? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return nominalLayoutHints[symbol]
    }

    public func setExternalLinkName(_ linkName: String, for symbol: SymbolID) {
        externalLinkNames[symbol] = linkName
    }

    public func clearExternalLinkName(for symbol: SymbolID) {
        externalLinkNames.removeValue(forKey: symbol)
    }

    public func externalLinkName(for symbol: SymbolID) -> String? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return externalLinkNames[symbol]
    }

    /// Marks an `.importedLibrary`-flagged global as storage-defined by this
    /// compilation (`.klib` globals have no precompiled object file behind
    /// them — their serialized IR bodies are materialized into KIR here).
    public func markKlibDefinedGlobal(_ symbol: SymbolID) {
        klibDefinedGlobalSymbols.insert(symbol)
    }

    public func isKlibDefinedGlobal(_ symbol: SymbolID) -> Bool {
        klibDefinedGlobalSymbols.contains(symbol)
    }

    public func setFunctionABIReturnType(_ type: TypeID, for symbol: SymbolID) {
        functionABIReturnTypes[symbol] = type
    }

    public func functionABIReturnType(for symbol: SymbolID) -> TypeID? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return functionABIReturnTypes[symbol]
    }

    public func setStdlibSpecialCallKind(_ kind: StdlibSpecialCallKind, for symbol: SymbolID) {
        stdlibSpecialCallKindsBySymbol[symbol] = kind
    }

    public func stdlibSpecialCallKind(forSymbol symbol: SymbolID) -> StdlibSpecialCallKind? {
        stdlibSpecialCallKindsBySymbol[symbol]
    }

    public func setTypeAliasUnderlyingType(_ type: TypeID, for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        typeAliasUnderlyingTypes[symbol] = type
    }

    public func typeAliasUnderlyingType(for symbol: SymbolID) -> TypeID? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        lock.lock()
        defer { lock.unlock() }
        return typeAliasUnderlyingTypes[symbol]
    }

    public func setTypeAliasTypeParameters(_ params: [SymbolID], for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        typeAliasTypeParameters[symbol] = params
    }

    public func typeAliasTypeParameters(for symbol: SymbolID) -> [SymbolID] {
        ensureLazyImportedMetadataLoaded(for: symbol)
        lock.lock()
        defer { lock.unlock() }
        return typeAliasTypeParameters[symbol] ?? []
    }

    public func setParentSymbol(_ parent: SymbolID, for child: SymbolID) {
        parentSymbols[child] = parent
    }

    public func parentSymbol(for child: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: child)
        return parentSymbols[child]
    }

    public func setBackingFieldSymbol(_ backingField: SymbolID, for property: SymbolID) {
        backingFieldSymbols[property] = backingField
    }

    public func backingFieldSymbol(for property: SymbolID) -> SymbolID? {
        backingFieldSymbols[property]
    }

    public func setDelegateStorageSymbol(_ storage: SymbolID, for property: SymbolID) {
        delegateStorageSymbols[property] = storage
    }

    public func delegateStorageSymbol(for property: SymbolID) -> SymbolID? {
        delegateStorageSymbols[property]
    }

    public func setDelegateGetValueSymbol(_ accessor: SymbolID, for property: SymbolID) {
        delegateGetValueSymbols[property] = accessor
    }

    public func delegateGetValueSymbol(for property: SymbolID) -> SymbolID? {
        delegateGetValueSymbols[property]
    }

    public func setDelegateSetValueSymbol(_ accessor: SymbolID, for property: SymbolID) {
        delegateSetValueSymbols[property] = accessor
    }

    public func delegateSetValueSymbol(for property: SymbolID) -> SymbolID? {
        delegateSetValueSymbols[property]
    }

    public func setDelegateProvideDelegateSymbol(_ accessor: SymbolID, for property: SymbolID) {
        delegateProvideDelegateSymbols[property] = accessor
    }

    public func delegateProvideDelegateSymbol(for property: SymbolID) -> SymbolID? {
        delegateProvideDelegateSymbols[property]
    }

    public func setExtensionPropertyReceiverType(_ type: TypeID, for property: SymbolID) {
        extensionPropertyReceiverTypes[property] = type
    }

    public func extensionPropertyReceiverType(for property: SymbolID) -> TypeID? {
        ensureLazyImportedMetadataLoaded(for: property)
        return extensionPropertyReceiverTypes[property]
    }

    public func hasExtensionPropertyReceiver(_ property: SymbolID) -> Bool {
        declaredExtensionProperties.contains(property) || extensionPropertyReceiverTypes[property] != nil
    }

    public func setExtensionPropertyGetterAccessor(_ accessor: SymbolID, for property: SymbolID) {
        extensionPropertyGetterAccessors[property] = accessor
    }

    public func extensionPropertyGetterAccessor(for property: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: property)
        return extensionPropertyGetterAccessors[property]
    }

    public func setExtensionPropertySetterAccessor(_ accessor: SymbolID, for property: SymbolID) {
        extensionPropertySetterAccessors[property] = accessor
    }

    public func extensionPropertySetterAccessor(for property: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: property)
        return extensionPropertySetterAccessors[property]
    }

    public func setAccessorOwnerProperty(_ propertySymbol: SymbolID, for accessorSymbol: SymbolID) {
        accessorOwnerProperties[accessorSymbol] = propertySymbol
    }

    public func accessorOwnerProperty(for accessorSymbol: SymbolID) -> SymbolID? {
        accessorOwnerProperties[accessorSymbol]
    }

    public func setTypeParameterUpperBounds(_ bounds: [TypeID], for symbol: SymbolID) {
        var uniqueBounds: [TypeID] = []
        uniqueBounds.reserveCapacity(bounds.count)
        for bound in bounds where !uniqueBounds.contains(bound) {
            uniqueBounds.append(bound)
        }
        typeParameterUpperBoundsMap[symbol] = uniqueBounds
    }

    public func typeParameterUpperBound(for symbol: SymbolID) -> TypeID? {
        typeParameterUpperBoundsMap[symbol]?.first
    }

    public func typeParameterUpperBounds(for symbol: SymbolID) -> [TypeID] {
        typeParameterUpperBoundsMap[symbol] ?? []
    }

    /// DEBT-SEMA-002: header collection resolves a type parameter's bounds (and can see
    /// there is more than one) long before class inheritance edges are bound (see
    /// `bindInheritanceEdges`, which runs afterwards in `runValidationPasses`). Recording the
    /// symbol here defers the actual mutual-exclusivity check until inheritance edges exist,
    /// so `TypeSystem.isSubtype` sees a fully-populated class hierarchy instead of treating
    /// every not-yet-linked class pair as unrelated.
    public func recordTypeParameterForBoundConflictCheck(_ symbol: SymbolID, declSite: SourceRange?) {
        pendingTypeParameterBoundConflictChecks.append((symbol, declSite))
    }

    public func typeParametersPendingBoundConflictCheck() -> [(symbol: SymbolID, declSite: SourceRange?)] {
        pendingTypeParameterBoundConflictChecks
    }

    public func setSourceFileID(_ fileID: FileID, for symbol: SymbolID) {
        sourceFileIDs[symbol] = fileID
    }

    public func sourceFileID(for symbol: SymbolID) -> FileID? {
        sourceFileIDs[symbol]
    }

    public func setModuleFQN(_ moduleFQN: InternedString, for symbol: SymbolID) {
        moduleFQNames[symbol] = moduleFQN
    }

    public func moduleFQN(for symbol: SymbolID) -> InternedString? {
        moduleFQNames[symbol]
    }

    public func setAnnotations(_ annotations: [MetadataAnnotationRecord], for symbol: SymbolID) {
        annotationsStorage[symbol] = annotations
    }

    public func annotations(for symbol: SymbolID) -> [MetadataAnnotationRecord] {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return annotationsStorage[symbol] ?? []
    }

    public func setCompanionObjectSymbol(_ companion: SymbolID, for owner: SymbolID) {
        companionObjectSymbols[owner] = companion
    }

    public func companionObjectSymbol(for owner: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: owner)
        return companionObjectSymbols[owner]
    }

    public func setOuterInstanceFieldSymbol(_ field: SymbolID, for innerClass: SymbolID) {
        outerInstanceFieldSymbols[innerClass] = field
    }

    /// The `$outer` field symbol holding `innerClass`'s enclosing-instance
    /// link, or `nil` when `innerClass` is not an `inner class`.
    public func outerInstanceFieldSymbol(for innerClass: SymbolID) -> SymbolID? {
        outerInstanceFieldSymbols[innerClass]
    }

    public func setObjectInitializerSymbol(_ initializer: SymbolID, for object: SymbolID) {
        objectInitializerSymbols[object] = initializer
    }

    public func objectInitializerSymbol(for object: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: object)
        return objectInitializerSymbols[object]
    }

    public func setObjectLazyInitializerSymbol(_ initializer: SymbolID, for object: SymbolID) {
        objectLazyInitializerSymbols[object] = initializer
    }

    public func objectLazyInitializerSymbol(for object: SymbolID) -> SymbolID? {
        objectLazyInitializerSymbols[object]
    }

    public func setCompanionObjectInitializerSymbol(_ initializer: SymbolID, for owner: SymbolID) {
        companionObjectInitializerSymbols[owner] = initializer
    }

    public func companionObjectInitializerSymbol(for owner: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: owner)
        return companionObjectInitializerSymbols[owner]
    }

    public func setEnumStaticInitSymbol(_ initializer: SymbolID, for owner: SymbolID) {
        enumStaticInitSymbols[owner] = initializer
    }

    public func enumStaticInitSymbol(for owner: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: owner)
        return enumStaticInitSymbols[owner]
    }

    public func setValueClassUnderlyingType(_ type: TypeID, for symbol: SymbolID) {
        valueClassUnderlyingTypes[symbol] = type
    }

    public func valueClassUnderlyingType(for symbol: SymbolID) -> TypeID? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return valueClassUnderlyingTypes[symbol]
    }

    /// Whether a value class directly implements at least one interface.
    ///
    /// Such a value class must keep its full boxed representation (vtable /
    /// itable registered via `kk_object_new`, same as a regular class) rather
    /// than being unboxed to its bare underlying primitive: an unboxed
    /// primitive has no itable to dispatch through when the value is later
    /// used as the interface type. Value classes are `final` in Kotlin, so
    /// checking direct supertypes is sufficient — there is no deeper
    /// interface-inheritance chain to walk.
    public func valueClassImplementsInterface(_ symbol: SymbolID) -> Bool {
        directSupertypes(for: symbol).contains { self.symbol($0)?.kind == .interface }
    }

    /// Returns `symbol`'s underlying primitive type only when it's safe to
    /// treat the value class as unboxed — i.e. it has a recorded underlying
    /// type AND implements no interface. Prefer this over
    /// `valueClassUnderlyingType(for:)` at every box/unbox decision site
    /// (`ValueClassUnboxingPass`, `resolveValueClassKind`, runtime type-check
    /// token classification) so they all agree on which value classes stay
    /// boxed; a mismatch between sites reintroduces the box/unbox corruption
    /// this method was added to prevent.
    public func effectiveValueClassUnderlyingType(for symbol: SymbolID) -> TypeID? {
        guard let underlying = valueClassUnderlyingTypes[symbol] else { return nil }
        guard !valueClassImplementsInterface(symbol) else { return nil }
        return underlying
    }

    public func setSealedSubclasses(_ subclasses: [SymbolID], for symbol: SymbolID) {
        sealedSubclassesStorage[symbol] = subclasses
    }

    public func setConstValueExprKind(_ kind: KIRExprKind, for symbol: SymbolID) {
        constValueExprKinds[symbol] = kind
    }

    public func constValueExprKind(for symbol: SymbolID) -> KIRExprKind? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return constValueExprKinds[symbol]
    }

    public func sealedSubclasses(for symbol: SymbolID) -> [SymbolID]? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return sealedSubclassesStorage[symbol]
    }

    /// Mark a property symbol as having a delegate with a `provideDelegate` operator.
    public func setHasProvideDelegate(for property: SymbolID) {
        delegateHasProvideDelegate.insert(property)
    }

    /// Returns whether the delegate type of the given property defines a `provideDelegate` operator.
    public func hasProvideDelegate(for property: SymbolID) -> Bool {
        delegateHasProvideDelegate.contains(property)
    }

    /// Link an `expect` declaration to its matching `actual` declaration.
    public func setExpectActualLink(expect: SymbolID, actual: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        expectActualLinks[expect] = actual
    }

    /// Returns the `actual` symbol linked to the given `expect` symbol, if any.
    public func actualSymbol(for expect: SymbolID) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return expectActualLinks[expect]
    }


    public func setContractNonNullEffect(_ effect: ContractNonNullEffect, for function: SymbolID) {
        contractNonNullEffects[function] = effect
    }

    public func addContractImplicationEffect(_ effect: ContractImplicationEffect, for function: SymbolID) {
        var effects = contractImplicationEffects[function] ?? []
        if !effects.contains(effect) { effects.append(effect) }
        contractImplicationEffects[function] = effects
    }

    public func contractImplicationEffects(for function: SymbolID) -> [ContractImplicationEffect] {
        contractImplicationEffects[function] ?? []
    }

    public func contractNonNullEffect(for function: SymbolID) -> ContractNonNullEffect? {
        contractNonNullEffects[function]
    }

    public func setContractReturnsEffect(_ effect: ContractReturnsEffect, for function: SymbolID) {
        contractReturnsEffects[function] = effect
    }

    public func contractReturnsEffect(for function: SymbolID) -> ContractReturnsEffect? {
        contractReturnsEffects[function]
    }

    /// STDLIB-592: Record a `callsInPlace` effect for a function's lambda parameter.
    public func addContractCallsInPlaceEffect(_ effect: ContractCallsInPlaceEffect, for function: SymbolID) {
        var effects = contractCallsInPlaceEffects[function] ?? []
        if !effects.contains(effect) { effects.append(effect) }
        contractCallsInPlaceEffects[function] = effects
    }

    /// STDLIB-592: Returns the `callsInPlace` effects recorded for a function, if any.
    public func contractCallsInPlaceEffects(for function: SymbolID) -> [ContractCallsInPlaceEffect] {
        contractCallsInPlaceEffects[function] ?? []
    }

    /// STDLIB-593: Record that a function has a `returnsNotNull` contract effect.
    public func setContractReturnsNotNull(for function: SymbolID) {
        contractReturnsNotNullEffects.insert(function)
    }

    /// STDLIB-591: Record a `returns() implies condition` effect where the
    /// condition is a Boolean parameter at the given index.
    public func setContractConditionEffect(_ effect: ContractConditionEffect, for function: SymbolID) {
        contractConditionEffects[function] = effect
    }

    /// STDLIB-591: Returns the `returns() implies condition` effect recorded
    /// for a function, if any.
    public func contractConditionEffect(for function: SymbolID) -> ContractConditionEffect? {
        contractConditionEffects[function]
    }

    /// Returns all symbol IDs of a given kind.
    public func symbols(ofKind kind: SymbolKind) -> [SymbolID] {
        byKind[kind] ?? []
    }

    /// Returns all direct child symbol IDs whose fqName parent prefix matches `parentFQName`.
    public func children(ofFQName parentFQName: [InternedString]) -> [SymbolID] {
        byParentFQName[parentFQName] ?? []
    }

    /// Returns all symbol IDs declared at the given source range.
    public func symbols(atDeclSite site: SourceRange) -> [SymbolID] {
        byDeclSite[site] ?? []
    }

    /// Returns true when the symbol represents a real Kotlin declaration
    /// (either bundled/user source or an imported library symbol), as opposed
    /// to a synthetic runtime stub. Imported library symbols are treated as
    /// source-backed because they carry the ABI name of the originally
    /// compiled declaration. Symbols with a `declSite` are source-backed even
    /// when they carry an explicit `externalLinkName` (e.g. `@KsSymbolName`
    /// bundled stdlib functions); synthetic stubs have no `declSite`.
    public func isSourceBackedSymbol(_ symbolID: SymbolID) -> Bool {
        guard let symbol = self.symbol(symbolID) else { return false }
        if symbol.flags.contains(.importedLibrary) { return true }
        return symbol.declSite != nil
    }
}
