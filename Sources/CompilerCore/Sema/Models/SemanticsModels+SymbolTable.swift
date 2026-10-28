// swiftlint:disable file_length
import Foundation

extension SymbolTable {
    /// Anonymous function literals are represented by local functions. A
    /// source label can replace the internal name, so literal semantics come
    /// from either the retained internal name or the synthetic marker.
    public func isAnonymousFunction(_ symbolID: SymbolID, interner: StringInterner) -> Bool {
        guard let symbol = symbol(symbolID) else { return false }
        return symbol.kind == .function
            && symbol.flags.contains(.localFunction)
            && (symbol.flags.contains(.synthetic)
                || interner.resolve(symbol.name).hasPrefix("__AnonymousFunction_"))
    }

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
        // The owner edges below are restored at shell registration, so the
        // non-forcing reads answer pending imports the same as decoded ones.
        // Property accessors are parented by their property, not its owner.
        if let property = parentSymbolIfKnown(for: callee),
           symbol(property)?.kind == .property,
           symbol(property)?.flags.contains(.memberExtension) == true,
           let owner = parentSymbolIfKnown(for: property),
           let ownerInfo = symbol(owner),
           [.class, .interface, .enumClass, .object].contains(ownerInfo.kind)
        {
            return owner
        }
        guard symbol(callee)?.flags.contains(.memberExtension) == true else {
            return nil
        }
        // A member-extension *property* itself (e.g. `val String.cstr` declared
        // on MemScope) has its dispatch owner as its direct parent.
        if symbol(callee)?.kind == .property,
           let owner = parentSymbolIfKnown(for: callee),
           let ownerInfo = symbol(owner),
           [.class, .interface, .enumClass, .object].contains(ownerInfo.kind)
        {
            return owner
        }
        guard let signature = functionSignature(for: callee),
              signature.receiverType != nil,
              let owner = parentSymbolIfKnown(for: callee),
              let ownerInfo = symbol(owner),
              [.class, .interface, .enumClass, .object].contains(ownerInfo.kind),
              symbol(callee)?.flags.contains(.extensionMemberAlias) != true
        else { return nil }
        return owner
    }
}

/// Arity-based member keys (bundled-overlap checks) can be answered from this
/// shape without materializing the declaration body.
struct ImportedMemberIndexShape: Codable {
    let arity: Int
    let receiverOwnerFQName: [InternedString]?
    let hasDefaultArguments: Bool

    init(arity: Int, receiverOwnerFQName: [InternedString]?, hasDefaultArguments: Bool = false) {
        self.arity = arity
        self.receiverOwnerFQName = receiverOwnerFQName
        self.hasDefaultArguments = hasDefaultArguments
    }
}

struct SemaSnapshotSymbol: Codable {
    let id: SymbolID
    let kind: SymbolKind
    let name: String
    let fqName: [String]
    let visibility: Visibility
    let flags: SymbolFlags
}

struct SemaSnapshotConstValue: Codable {
    enum Value: Codable {
        case int(Int64)
        case long(Int64)
        case uint(UInt64)
        case ulong(UInt64)
        case float(Double)
        case double(Double)
        case char(UInt32)
        case bool(Bool)
        case string(String)
        case symbol(SymbolID)
        case externAddress(String)
        case temporary(Int32)
        case null
        case unit
    }

    let value: Value

    init(_ kind: KIRExprKind, interner: StringInterner) {
        value = switch kind {
        case let .intLiteral(value): .int(value)
        case let .longLiteral(value): .long(value)
        case let .uintLiteral(value): .uint(value)
        case let .ulongLiteral(value): .ulong(value)
        case let .floatLiteral(value): .float(value)
        case let .doubleLiteral(value): .double(value)
        case let .charLiteral(value): .char(value)
        case let .boolLiteral(value): .bool(value)
        case let .stringLiteral(value): .string(interner.resolve(value))
        case let .symbolRef(value): .symbol(value)
        case let .externSymbolAddress(value): .externAddress(interner.resolve(value))
        case let .temporary(value): .temporary(value)
        case .null: .null
        case .unit: .unit
        }
    }

    func materialize(interner: StringInterner, mapSymbol: (SymbolID) -> SymbolID) -> KIRExprKind {
        switch value {
        case let .int(value): .intLiteral(value)
        case let .long(value): .longLiteral(value)
        case let .uint(value): .uintLiteral(value)
        case let .ulong(value): .ulongLiteral(value)
        case let .float(value): .floatLiteral(value)
        case let .double(value): .doubleLiteral(value)
        case let .char(value): .charLiteral(value)
        case let .bool(value): .boolLiteral(value)
        case let .string(value): .stringLiteral(interner.intern(value))
        case let .symbol(value): .symbolRef(mapSymbol(value))
        case let .externAddress(value): .externSymbolAddress(interner.intern(value))
        case let .temporary(value): .temporary(value)
        case .null: .null
        case .unit: .unit
        }
    }
}

struct SemaSnapshotMemberIndexShape: Codable {
    let arity: Int
    let receiverOwnerFQName: [String]?
    let hasDefaultArguments: Bool
}

struct SymbolTableSemaSnapshot: Codable {
    let symbols: [SemaSnapshotSymbol]
    let functionSignatures: [SymbolID: FunctionSignature]
    let propertyTypes: [SymbolID: TypeID]
    let propertyHasCustomGetter: [SymbolID: Bool]
    let propertySetterVisibilities: [SymbolID: Visibility]
    let directSupertypes: [SymbolID: [SymbolID]]
    let supertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]]
    let extensionFunctionTypeSupertypeSymbols: Set<SymbolID>?
    let nominalLayouts: [SymbolID: NominalLayout]
    let nominalLayoutHints: [SymbolID: NominalLayoutHint]
    let externalLinkNames: [SymbolID: String]
    let functionABIReturnTypes: [SymbolID: TypeID]
    let stdlibSpecialCallKindsBySymbol: [SymbolID: StdlibSpecialCallKind]
    let typeAliasUnderlyingTypes: [SymbolID: TypeID]
    let typeAliasTypeParameters: [SymbolID: [SymbolID]]
    let parentSymbols: [SymbolID: SymbolID]
    let backingFieldSymbols: [SymbolID: SymbolID]
    let delegateStorageSymbols: [SymbolID: SymbolID]
    let delegatePropertiesByStorageSymbol: [SymbolID: SymbolID]
    let delegateGetValueSymbols: [SymbolID: SymbolID]
    let delegateSetValueSymbols: [SymbolID: SymbolID]
    let delegateProvideDelegateSymbols: [SymbolID: SymbolID]
    let accessorOwnerProperties: [SymbolID: SymbolID]
    let extensionPropertyReceiverTypes: [SymbolID: TypeID]
    let importedExtensionReceiverProperties: Set<SymbolID>
    let declaredExtensionProperties: Set<SymbolID>
    let extensionPropertyGetterAccessors: [SymbolID: SymbolID]
    let extensionPropertySetterAccessors: [SymbolID: SymbolID]
    let typeParameterUpperBoundsMap: [SymbolID: [TypeID]]
    let importedStdlibSymbolIDs: Set<SymbolID>
    let moduleFQNames: [SymbolID: String]
    let annotationsStorage: [SymbolID: [MetadataAnnotationRecord]]
    let companionObjectSymbols: [SymbolID: SymbolID]
    let outerInstanceFieldSymbols: [SymbolID: SymbolID]
    let objectInitializerSymbols: [SymbolID: SymbolID]
    let objectLazyInitializerSymbols: [SymbolID: SymbolID]
    let companionObjectInitializerSymbols: [SymbolID: SymbolID]
    let enumStaticInitSymbols: [SymbolID: SymbolID]
    let enumEntryDispatchTargets: [SymbolID: [EnumEntryDispatchTarget]]
    let enumEntryDispatchBaseSymbols: [SymbolID: SymbolID]
    let valueClassUnderlyingTypes: [SymbolID: TypeID]
    let sealedSubclassesStorage: [SymbolID: [SymbolID]]
    let constValueExprKinds: [SymbolID: SemaSnapshotConstValue]
    let delegateHasProvideDelegate: Set<SymbolID>
    let expectActualLinks: [SymbolID: SymbolID]
    let expectActualDefaultArgumentOwners: [SymbolID: SymbolID]
    let contractNonNullEffects: [SymbolID: ContractNonNullEffect]
    let contractImplicationEffects: [SymbolID: [ContractImplicationEffect]]
    let contractReturnsEffects: [SymbolID: ContractReturnsEffect]
    let contractCallsInPlaceEffects: [SymbolID: [ContractCallsInPlaceEffect]]
    let contractReturnsNotNullEffects: Set<SymbolID>
    let contractConditionEffects: [SymbolID: ContractConditionEffect]
    let importedNominalsWithoutInitializers: Set<SymbolID>
    let importedNominalsWithIncompleteInitializerInfo: Set<SymbolID>
    let importedMemberIndexShapes: [SymbolID: SemaSnapshotMemberIndexShape]
    let delegatedInterfacesByClass: [SymbolID: Set<SymbolID>]
    let klibDefinedGlobalSymbols: Set<SymbolID>
    let overrideDefaultsBaseSymbols: [SymbolID: SymbolID]
    let inheritedDefaultsByReceiver: [TypeID: [SymbolID: SymbolID]]
}

/// A compact-indexed imported library whose records register on demand.
///
/// SymbolTable query paths drain matching entries through these hooks before
/// reading their indexes, so a shell is defined only when a lookup can
/// actually reach it — the eager `registerShells` pass over every index entry
/// is replaced by per-query registration.
protocol IndexedLibraryEntryProvider: AnyObject {
    /// Position on the library search path. Drains issued while an earlier
    /// library is still being imported must not see records from later
    /// libraries, so each drain is capped by `SymbolTable.importDrainEpoch`.
    var importOrder: Int { get }
    /// Register every pending entry whose FQ name equals `fqName`.
    func drainEntries(fqName: [InternedString])
    /// Register every pending entry declared directly under `parentFQName`,
    /// including extension records reparented to that nominal owner.
    func drainChildren(parentFQName: [InternedString])
    /// Register every pending declaration-kind entry with this simple name.
    func drainEntries(shortName: InternedString)
    /// Whether the index contains declarations nested under `fqName` — the
    /// signal that justifies synthesizing a package shell for that path.
    func containsEntriesNested(under fqName: [InternedString]) -> Bool
    /// Package-prefix paths nested directly under `parentFQName`, in index
    /// order. Used when a children drain must expose child package shells.
    func packagePrefixes(under parentFQName: [InternedString]) -> [[InternedString]]
    /// Module name stamped onto a synthesized package for `fqName`, or nil
    /// when this library does not contribute that prefix (or has no module).
    func packageModuleFQN(for fqName: [InternedString]) -> InternedString?
    /// Register every record from this library. Used only when producing a
    /// persistent stdlib snapshot, where the import-time graph must be complete.
    func materializeAll(into symbols: SymbolTable)
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
    private var propertySetterVisibilities: [SymbolID: Visibility] = [:]
    private var directSupertypes: [SymbolID: [SymbolID]] = [:]
    /// Kept in sync by `setDirectSupertypes` so `directSubtypes(of:)` reads a
    /// precomputed list instead of scanning every nominal type in the module
    /// on each call.
    private var directSubtypesIndex: [SymbolID: [SymbolID]] = [:]
    private var supertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]
    private var extensionFunctionTypeSupertypeSymbols: Set<SymbolID> = []
    private var nominalLayouts: [SymbolID: NominalLayout] = [:]
    private var nominalLayoutHints: [SymbolID: NominalLayoutHint] = [:]
    private var externalLinkNames: [SymbolID: String] = [:]
    /// Backend ABI return type for functions whose compiled calling convention
    /// differs from their source-level return type (e.g. raw `Int` string handles).
    private var functionABIReturnTypes: [SymbolID: TypeID] = [:]
    private var stdlibSpecialCallKindsBySymbol: [SymbolID: StdlibSpecialCallKind] = [:]
    private var typeAliasUnderlyingTypes: [SymbolID: TypeID] = [:]
    private var typeAliasTypeParameters: [SymbolID: [SymbolID]] = [:]
    private var childrenByParent: [SymbolID: Set<SymbolID>] = [:]
    private var parentSymbols: [SymbolID: SymbolID] = [:]
    private var backingFieldSymbols: [SymbolID: SymbolID] = [:]
    private var delegateStorageSymbols: [SymbolID: SymbolID] = [:]
    private var delegatePropertiesByStorageSymbol: [SymbolID: SymbolID] = [:]
    private var delegateGetValueSymbols: [SymbolID: SymbolID] = [:]
    private var delegateSetValueSymbols: [SymbolID: SymbolID] = [:]
    private var delegateProvideDelegateSymbols: [SymbolID: SymbolID] = [:]
    private var accessorOwnerProperties: [SymbolID: SymbolID] = [:]
    private var extensionPropertyReceiverTypes: [SymbolID: TypeID] = [:]
    /// Imported properties whose compact-index record carries a receiver
    /// signature. Registration records the fact so membership checks stay
    /// correct for shells whose receiver type has not been decoded yet.
    private var importedExtensionReceiverProperties: Set<SymbolID> = []
    private var declaredExtensionProperties: Set<SymbolID> = []
    private var extensionPropertyGetterAccessors: [SymbolID: SymbolID] = [:]
    private var extensionPropertySetterAccessors: [SymbolID: SymbolID] = [:]
    private var typeParameterUpperBoundsMap: [SymbolID: [TypeID]] = [:]
    private var pendingTypeParameterBoundConflictChecks: [(symbol: SymbolID, declSite: SourceRange?)] = []
    private var sourceFileIDs: [SymbolID: FileID] = [:]
    /// Selected symbols imported from the validated stdlib artifact, including
    /// indexed declarations whose bodies have not been materialized yet.
    private var importedStdlibSymbolIDs: Set<SymbolID> = []
    /// Runtime reflection records already embedded in a linked native library object.
    private var importedRuntimeReflectionScopes: [SymbolID: String] = [:]
    private var moduleFQNames: [SymbolID: InternedString] = [:]
    private var byModuleFQN: [InternedString: [SymbolID]] = [:]
    private var annotationsStorage: [SymbolID: [MetadataAnnotationRecord]] = [:]
    private var companionObjectSymbols: [SymbolID: SymbolID] = [:]
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
    /// Actual functions inherit call-site defaults from their paired expect
    /// declaration, whose source AST owns the expressions and default stub.
    private var expectActualDefaultArgumentOwners: [SymbolID: SymbolID] = [:]
    private var contractNonNullEffects: [SymbolID: ContractNonNullEffect] = [:]
    private var contractImplicationEffects: [SymbolID: [ContractImplicationEffect]] = [:]
    private var contractReturnsEffects: [SymbolID: ContractReturnsEffect] = [:]
    private var contractCallsInPlaceEffects: [SymbolID: [ContractCallsInPlaceEffect]] = [:]
    private var contractReturnsNotNullEffects: Set<SymbolID> = []
    private var contractConditionEffects: [SymbolID: ContractConditionEffect] = [:]
    private var lazyImportedMetadataLoader: ((SymbolID) -> Void)?
    private var lazyImportedMetadataLoaded: Set<SymbolID> = []
    private var lazyImportedMetadataLoadInProgress: Set<SymbolID> = []
    /// Synthetic-bootstrap work postponed until the imported shell it touches
    /// is materialized (KUU-2673). The pre-materialization queue runs just
    /// before the shell's record is applied — matching the eager bootstrap's
    /// "synthetic state first, metadata merge second" ordering — while the
    /// post-materialization queue runs after the record is fully applied so
    /// deferred reads observe the decoded signatures and annotations.
    private var pendingShellWorkBeforeMaterialization: [SymbolID: [() -> Void]] = [:]
    private var pendingShellWorkAfterMaterialization: [SymbolID: [() -> Void]] = [:]
    private var indexedImportedNominals: Set<SymbolID> = []
    /// Compact-index shells whose complete record has not been applied yet.
    /// Unlike `lazyImportedMetadataLoaded` (which only tracks symbols that
    /// went through `ensureLazyImportedMetadataLoaded`), this set is fixed at
    /// loader registration, so membership minus `lazyImportedMetadataLoaded`
    /// identifies shells still decodable on demand.
    private var lazyImportedShells: Set<SymbolID> = []
    /// Compact-index libraries whose records register on demand. Each lookup
    /// path drains pending entries for the queried key before reading its
    /// index, so unreferenced records never allocate a symbol.
    private var indexedLibraryProviders: [IndexedLibraryEntryProvider] = []
    /// Drains only see providers at or before this search-path position while
    /// library import is in flight; `.max` afterwards.
    var importDrainEpoch: Int = .max
    /// Reentrancy guards: a drain registers symbols, whose own parent/link
    /// restoration queries other keys and must not re-drain the key already
    /// in flight. Claimed entries are consumed, so an in-flight key simply
    /// has nothing left to register.
    private var fqNameDrainInProgress: Set<[InternedString]> = []
    private var childrenDrainInProgress: Set<[InternedString]> = []
    private var shortNameDrainInProgress: Set<InternedString> = []
    private var importedLayoutSynthesizer: ((SymbolID) -> Void)?
    private var importedLayoutSynthesisInProgress = false
    private var importedNominalsWithoutInitializers: Set<SymbolID> = []
    /// Nominals whose index record predates the initializer section: the
    /// index can neither list nor rule out eager initializers, so scans must
    /// retain the semantic-loader fallback for these symbols only.
    private var importedNominalsWithIncompleteInitializerInfo: Set<SymbolID> = []
    /// Consulted by arity-key builders so they never force body materialization.
    private var importedMemberIndexShapes: [SymbolID: ImportedMemberIndexShape] = [:]
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

    // Use-site defaults must never change the superclass declaration's signature.
    private var inheritedDefaultsByReceiver: [TypeID: [SymbolID: SymbolID]] = [:]

    /// Thread safety lock for concurrent access. Recursive because the lazy
    /// imported-metadata loader re-enters this table (`define`, `lookupAll`,
    /// `setFunctionSignature`, ...) while materializing a symbol, and that
    /// materialization can be triggered from inside `define`'s critical
    /// section (e.g. `canCoexistAsOverload` → `extensionPropertyReceiverType`).
    /// A plain NSLock would self-deadlock on that path.
    private let lock = NSRecursiveLock()

    /// Copy-on-write snapshot at the module barrier. Lazy loader callbacks
    /// capture module-owned types/inline stores and cannot cross this boundary.
    func makeSemaWorkerSymbols() -> SymbolTable {
        lock.lock()
        defer { lock.unlock() }
        precondition(lazyImportedMetadataLoader == nil)
        let worker = SymbolTable()
        worker.symbolsStorage = symbolsStorage
        worker.byFQName = byFQName
        worker.byShortName = byShortName
        worker.byKind = byKind
        worker.byParentFQName = byParentFQName
        worker.byDeclSite = byDeclSite
        worker.functionSignatures = functionSignatures
        worker.valueParameterOwners = valueParameterOwners
        worker.propertyTypes = propertyTypes
        worker.propertyHasCustomGetter = propertyHasCustomGetter
        worker.propertySetterVisibilities = propertySetterVisibilities
        worker.directSupertypes = directSupertypes
        worker.directSubtypesIndex = directSubtypesIndex
        worker.supertypeTypeArgsMap = supertypeTypeArgsMap
        worker.nominalLayouts = nominalLayouts
        worker.nominalLayoutHints = nominalLayoutHints
        worker.externalLinkNames = externalLinkNames
        worker.functionABIReturnTypes = functionABIReturnTypes
        worker.stdlibSpecialCallKindsBySymbol = stdlibSpecialCallKindsBySymbol
        worker.typeAliasUnderlyingTypes = typeAliasUnderlyingTypes
        worker.typeAliasTypeParameters = typeAliasTypeParameters
        worker.childrenByParent = childrenByParent
        worker.parentSymbols = parentSymbols
        worker.backingFieldSymbols = backingFieldSymbols
        worker.delegateStorageSymbols = delegateStorageSymbols
        worker.delegatePropertiesByStorageSymbol = delegatePropertiesByStorageSymbol
        worker.delegateGetValueSymbols = delegateGetValueSymbols
        worker.delegateSetValueSymbols = delegateSetValueSymbols
        worker.delegateProvideDelegateSymbols = delegateProvideDelegateSymbols
        worker.accessorOwnerProperties = accessorOwnerProperties
        worker.extensionPropertyReceiverTypes = extensionPropertyReceiverTypes
        worker.importedExtensionReceiverProperties = importedExtensionReceiverProperties
        worker.declaredExtensionProperties = declaredExtensionProperties
        worker.extensionPropertyGetterAccessors = extensionPropertyGetterAccessors
        worker.extensionPropertySetterAccessors = extensionPropertySetterAccessors
        worker.typeParameterUpperBoundsMap = typeParameterUpperBoundsMap
        worker.pendingTypeParameterBoundConflictChecks = pendingTypeParameterBoundConflictChecks
        worker.sourceFileIDs = sourceFileIDs
        worker.importedStdlibSymbolIDs = importedStdlibSymbolIDs
        worker.importedRuntimeReflectionScopes = importedRuntimeReflectionScopes
        worker.moduleFQNames = moduleFQNames
        worker.byModuleFQN = byModuleFQN
        worker.annotationsStorage = annotationsStorage
        worker.companionObjectSymbols = companionObjectSymbols
        worker.outerInstanceFieldSymbols = outerInstanceFieldSymbols
        worker.objectInitializerSymbols = objectInitializerSymbols
        worker.objectLazyInitializerSymbols = objectLazyInitializerSymbols
        worker.companionObjectInitializerSymbols = companionObjectInitializerSymbols
        worker.enumStaticInitSymbols = enumStaticInitSymbols
        worker.enumEntryDispatchTargets = enumEntryDispatchTargets
        worker.enumEntryDispatchBaseSymbols = enumEntryDispatchBaseSymbols
        worker.valueClassUnderlyingTypes = valueClassUnderlyingTypes
        worker.sealedSubclassesStorage = sealedSubclassesStorage
        worker.constValueExprKinds = constValueExprKinds
        worker.delegateHasProvideDelegate = delegateHasProvideDelegate
        worker.expectActualLinks = expectActualLinks
        worker.expectActualDefaultArgumentOwners = expectActualDefaultArgumentOwners
        worker.contractNonNullEffects = contractNonNullEffects
        worker.contractImplicationEffects = contractImplicationEffects
        worker.contractReturnsEffects = contractReturnsEffects
        worker.contractCallsInPlaceEffects = contractCallsInPlaceEffects
        worker.contractReturnsNotNullEffects = contractReturnsNotNullEffects
        worker.contractConditionEffects = contractConditionEffects
        worker.lazyImportedMetadataLoaded = lazyImportedMetadataLoaded
        worker.lazyImportedMetadataLoadInProgress = lazyImportedMetadataLoadInProgress
        worker.lazyImportedShells = lazyImportedShells
        worker.importedNominalsWithoutInitializers = importedNominalsWithoutInitializers
        worker.importedNominalsWithIncompleteInitializerInfo = importedNominalsWithIncompleteInitializerInfo
        worker.importedMemberIndexShapes = importedMemberIndexShapes
        worker.delegatedInterfacesByClass = delegatedInterfacesByClass
        worker.klibDefinedGlobalSymbols = klibDefinedGlobalSymbols
        worker.overrideDefaultsBaseSymbols = overrideDefaultsBaseSymbols
        worker.inheritedDefaultsByReceiver = inheritedDefaultsByReceiver
        return worker
    }

    /// The module and each worker are sole writers of their own table.
    var symbolCount: Int { symbolsStorage.count }

    func workerLocalSymbols(since count: Int) -> [SemaWorkerLocalSymbol]? {
        var locals: [SemaWorkerLocalSymbol] = []
        for symbol in symbolsStorage.dropFirst(count) {
            guard symbol.kind == .local, let type = propertyTypes[symbol.id] else { return nil }
            locals.append(SemaWorkerLocalSymbol(symbol: symbol, type: type))
        }
        return locals
    }

    /// Replay allocations at their original declaration position, after string
    /// and type canonicalization. Earlier serial declarations may consume the
    /// same worker ordinal; never publish that ordinal directly.
    func mergeWorkerLocals(
        _ locals: [SemaWorkerLocalSymbol],
        strings: [InternedString: InternedString], types: [TypeID: TypeID]
    ) -> [SymbolID: SymbolID] {
        var mapping: [SymbolID: SymbolID] = [:]
        for local in locals {
            let symbol = local.symbol
            let canonical = define(
                kind: .local, name: strings[symbol.name] ?? symbol.name,
                fqName: symbol.fqName.map { strings[$0] ?? $0 },
                declSite: symbol.declSite, visibility: symbol.visibility, flags: symbol.flags
            )
            setPropertyType(types[local.type] ?? local.type, for: canonical)
            mapping[symbol.id] = canonical
        }
        return mapping
    }

    public init() {}

    /// The loader is intentionally callback-based so the metadata reader stays
    /// outside the symbol model and can reuse the normal import application path.
    func setLazyImportedMetadataLoader(
        alreadyLoaded: Set<SymbolID> = [],
        indexedNominals: Set<SymbolID> = [],
        lazyShells: Set<SymbolID> = [],
        _ loader: ((SymbolID) -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        indexedImportedNominals = indexedNominals
        // Union, not replace: `appendImportedBinding` already marks shells
        // registered ahead of the install (and tail-pass lookups between the
        // `importedBindings` snapshot and here can add more).
        lazyImportedShells.formUnion(lazyShells)
        importedLayoutSynthesizer = nil
        importedLayoutSynthesisInProgress = false
        lazyImportedMetadataLoader = loader
        lazyImportedMetadataLoaded = alreadyLoaded
        lazyImportedMetadataLoadInProgress.removeAll()
    }

    var hasLazyImportedMetadataLoader: Bool {
        lazyImportedMetadataLoader != nil
    }

    /// True while a table query can still lazily materialize imported state:
    /// compact-index drains register symbols on demand, lazy metadata shells
    /// decode bodies, and the imported-layout synthesizer writes nominal
    /// layouts — each of which mutates TypeSystem without synchronization.
    /// Parallel codegen workers therefore only run once this is false.
    public var hasLazySymbolMaterialization: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lazyImportedMetadataLoader != nil
            || importedLayoutSynthesizer != nil
            || !indexedLibraryProviders.isEmpty
    }

    /// Attaches a compact-index library whose entries register on demand.
    /// Providers must be added in search-path order.
    func addIndexedLibraryProvider(_ provider: IndexedLibraryEntryProvider) {
        lock.lock()
        defer { lock.unlock() }
        indexedLibraryProviders.append(provider)
    }

    /// Forces compact-index registration and metadata decoding for snapshot
    /// production. Ordinary compilations keep the indexed import lazy.
    func materializeAllIndexedLibraryState() {
        lock.lock()
        defer { lock.unlock() }
        importDrainEpoch = .max
        for provider in indexedLibraryProviders.sorted(by: { $0.importOrder < $1.importOrder }) {
            provider.materializeAll(into: self)
        }
        let pending = symbolsStorage
            .filter { $0.flags.contains(.importedLibrary) }
            .map(\.id)
        for symbol in pending where isUnmaterializedImportedShellLocked(symbol) {
            ensureLazyImportedMetadataLoaded(for: symbol)
        }
    }

    /// Registration-time mark for nominal shells drained after the lazy
    /// loader was installed — the set passed to
    /// `setLazyImportedMetadataLoader` only covers bindings already created
    /// at that point.
    func markIndexedImportedNominal(_ symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        indexedImportedNominals.insert(symbol)
    }

    /// Same growth for lazy shells of every kind: index providers keep
    /// appending pending bindings after `setLazyImportedMetadataLoader` took
    /// its `lazyShells` snapshot, and every pending-shell predicate
    /// (deferral, `hasPendingImportedMetadata`) must see them too.
    func markLazyImportedShell(_ symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        lazyImportedShells.insert(symbol)
    }

    /// Register pending index entries for `fqName`, then synthesize a package
    /// shell when the path only exists as a declaration prefix. Every lookup
    /// path that reads `byFQName` calls this first so unregistered shells
    /// stay invisible until they are actually reachable.
    ///
    /// `define` passes `synthesizePackage: false`: it drains pending entries
    /// so shadow and overload checks see them, but must not append a package
    /// ahead of the symbol it is mid-way through registering — the eager pass
    /// always placed packages after same-path declarations in `byFQName`.
    private func drainIndexedEntries(fqName: [InternedString], synthesizePackage: Bool = true) {
        guard !indexedLibraryProviders.isEmpty, !fqName.isEmpty,
              fqNameDrainInProgress.insert(fqName).inserted
        else { return }
        defer { fqNameDrainInProgress.remove(fqName) }
        for provider in indexedLibraryProviders where provider.importOrder <= importDrainEpoch {
            provider.drainEntries(fqName: fqName)
        }
        guard synthesizePackage else { return }
        let alreadyHasPackage = byFQName[fqName]?.contains(where: { symbol($0)?.kind == .package }) == true
        guard !alreadyHasPackage,
              indexedLibraryProviders.contains(where: {
                  $0.importOrder <= importDrainEpoch && $0.containsEntriesNested(under: fqName)
              })
        else { return }
        let package = define(
            kind: .package,
            name: fqName.last ?? .invalid,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        // The latest library on the search path contributing this prefix owns
        // the package's module tag, matching the eager synthetic-package pass.
        if let moduleFQN = indexedLibraryProviders.last(where: {
            $0.importOrder <= importDrainEpoch && $0.packageModuleFQN(for: fqName) != nil
        }).flatMap({ $0.packageModuleFQN(for: fqName) }) {
            setModuleFQN(moduleFQN, for: package)
        }
    }

    /// Register pending index entries declared directly under `parentFQName`
    /// (member declarations plus extension records reparented to a nominal
    /// owner at that path) and materialize child package shells, so
    /// `children(ofFQName:)`/`children(of:)` see the same membership the eager
    /// registration produced.
    private func drainIndexedChildren(parentFQName: [InternedString]) {
        guard !indexedLibraryProviders.isEmpty,
              childrenDrainInProgress.insert(parentFQName).inserted
        else { return }
        defer { childrenDrainInProgress.remove(parentFQName) }
        var claimedPrefixes: Set<[InternedString]> = []
        for provider in indexedLibraryProviders where provider.importOrder <= importDrainEpoch {
            provider.drainChildren(parentFQName: parentFQName)
            for prefix in provider.packagePrefixes(under: parentFQName) {
                claimedPrefixes.insert(prefix)
            }
        }
        // Each package prefix drains through the FQ-name path, which
        // synthesizes the package shell itself.
        for prefix in claimedPrefixes {
            drainIndexedEntries(fqName: prefix)
        }
    }

    private func drainIndexedEntries(shortName: InternedString) {
        guard !indexedLibraryProviders.isEmpty,
              shortNameDrainInProgress.insert(shortName).inserted
        else { return }
        defer { shortNameDrainInProgress.remove(shortName) }
        for provider in indexedLibraryProviders where provider.importOrder <= importDrainEpoch {
            provider.drainEntries(shortName: shortName)
        }
    }

    /// Whether any compact-index provider has entries nested under `fqName` —
    /// answers "this path is a package" for import validation without
    /// registering anything.
    func libraryIndexContainsEntriesNested(under fqName: [InternedString]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return indexedLibraryProviders.contains {
            $0.importOrder <= importDrainEpoch && $0.containsEntriesNested(under: fqName)
        }
    }

    func hasPendingImportedNominalMetadata(for symbol: SymbolID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lazyImportedMetadataLoader != nil
            && indexedImportedNominals.contains(symbol)
            && !lazyImportedMetadataLoaded.contains(symbol)
    }

    /// True while this symbol's imported body can still be lazily decoded.
    /// False for source declarations, eagerly applied imports, and shells
    /// already materialized through the loader. Reflection record generation
    /// uses this to skip declarations the compiled program cannot reach —
    /// decoding them here would materialize the entire imported surface.
    func hasPendingImportedMetadata(for symbol: SymbolID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lazyImportedMetadataLoader != nil
            && lazyImportedShells.contains(symbol)
            && !lazyImportedMetadataLoaded.contains(symbol)
    }

    /// True when `nominalLayout(for:)` owns this nominal's layout through the
    /// imported-layout synthesizer — a compact-index nominal (pending shell
    /// or already materialized) while a lazy imported-metadata loader is
    /// installed. `synthesizeNominalLayouts` skips these symbols: eagerly
    /// synthesizing them decodes member records the program may never use,
    /// and the on-demand callback produces the same layout at first real use.
    func hasOnDemandImportedNominalLayout(_ symbol: SymbolID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lazyImportedMetadataLoader != nil
            && indexedImportedNominals.contains(symbol)
    }

    func setImportedLayoutSynthesizer(_ synthesizer: @escaping (SymbolID) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        importedLayoutSynthesizer = synthesizer
    }

    func setImportedMemberIndexShape(_ shape: ImportedMemberIndexShape, for symbol: SymbolID) {
        importedMemberIndexShapes[symbol] = shape
    }

    func importedMemberIndexShape(for symbol: SymbolID) -> ImportedMemberIndexShape? {
        importedMemberIndexShapes[symbol]
    }

    func recordImportedNominalWithoutInitializers(_ symbol: SymbolID) {
        importedNominalsWithoutInitializers.insert(symbol)
    }

    /// False only when a complete compact index proves there are no eager
    /// initializer calls. Older indexes retain semantic-loader fallback.
    public func mayHaveImportedInitializers(for symbol: SymbolID) -> Bool {
        !importedNominalsWithoutInitializers.contains(symbol)
    }

    func recordImportedNominalIncompleteInitializerInfo(_ symbol: SymbolID) {
        importedNominalsWithIncompleteInitializerInfo.insert(symbol)
    }

    /// True for shells whose index entry cannot enumerate eager initializers
    /// (pre-v3 records and eager imports): only a body decode can discover
    /// them, so callers must use the forcing getters for these symbols.
    func importedInitializerInfoIsIncomplete(for symbol: SymbolID) -> Bool {
        importedNominalsWithIncompleteInitializerInfo.contains(symbol)
    }

    func ensureLazyImportedMetadataLoaded(for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        let loadSymbol = accessorOwnerProperties[symbol] ?? symbol
        guard let loader = lazyImportedMetadataLoader,
              !lazyImportedMetadataLoaded.contains(loadSymbol),
              !lazyImportedMetadataLoadInProgress.contains(loadSymbol)
        else {
            return
        }
        lazyImportedMetadataLoadInProgress.insert(loadSymbol)
        loader(loadSymbol)
        lazyImportedMetadataLoadInProgress.remove(loadSymbol)
        lazyImportedMetadataLoaded.insert(loadSymbol)
        lazyImportedMetadataLoaded.insert(symbol)
    }

    /// True while `symbol` is an imported-library record whose body has not
    /// been materialized yet — the cheap check shared by every
    /// defer-until-materialization callsite. Membership is keyed on
    /// `lazyImportedShells` (registered at loader install) rather than the
    /// `.importedLibrary` flag so eagerly applied imported records — which
    /// have no pending record to drain against — still run their work
    /// inline instead of losing it. `loadInProgress` membership is
    /// load-bearing: a deferred item that re-invokes its guarded call
    /// while its own shell is mid-load must run inline (for post-queue
    /// work the record is already applied by then), otherwise it
    /// re-enqueues against the same drain and loops forever.
    public func isUnmaterializedImportedShell(_ symbol: SymbolID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isUnmaterializedImportedShellLocked(symbol)
    }

    private func isUnmaterializedImportedShellLocked(_ symbol: SymbolID) -> Bool {
        lazyImportedMetadataLoader != nil
            && lazyImportedShells.contains(symbol)
            && !lazyImportedMetadataLoaded.contains(symbol)
            && !lazyImportedMetadataLoadInProgress.contains(symbol)
    }

    /// If `symbol` is an unmaterialized imported shell, enqueue `work` so it
    /// runs immediately before the shell's imported record is applied — the
    /// same point where the eager synthetic bootstrap wrote this data — and
    /// return true. Otherwise return false; the caller must run `work` itself.
    func deferUntilImportedShellMaterializes(_ symbol: SymbolID, work: @escaping () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isUnmaterializedImportedShellLocked(symbol) else {
            return false
        }
        pendingShellWorkBeforeMaterialization[symbol, default: []].append(work)
        return true
    }

    /// Same as `deferUntilImportedShellMaterializes`, but `work` runs after
    /// the shell's record has been fully applied, so it can read the decoded
    /// signatures, annotations and member metadata it patches.
    func deferUntilAfterImportedShellMaterializes(_ symbol: SymbolID, work: @escaping () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isUnmaterializedImportedShellLocked(symbol) else {
            return false
        }
        pendingShellWorkAfterMaterialization[symbol, default: []].append(work)
        return true
    }

    /// Convenience for the synthetic bootstrap's "does a member already exist
    /// at `fqName`" checks: when any candidate is still an unmaterialized
    /// imported shell, enqueues `work` on the first such shell so the check
    /// re-runs once its signature is available, and returns true. When every
    /// candidate is already materialized (or absent), returns false and the
    /// caller performs the check inline.
    func deferWorkUntilImportedMemberMaterializes(
        at fqName: [InternedString],
        work: @escaping () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Shells register through index-provider drains on lookup, so the
        // pending check must drain this path first — otherwise a member whose
        // shell has not been requested yet looks absent and the caller decodes
        // it eagerly instead of deferring.
        drainIndexedEntries(fqName: fqName, synthesizePackage: false)
        guard let pending = (byFQName[fqName] ?? []).first(where: {
            isUnmaterializedImportedShellLocked($0)
        }) else {
            return false
        }
        pendingShellWorkAfterMaterialization[pending, default: []].append(work)
        return true
    }

    /// Runs everything queued by `deferUntilImportedShellMaterializes` for
    /// `symbol`. Called by the lazy metadata loader right before the imported
    /// record is applied; deferred items re-check `defer` guards, so
    /// re-enqueueing from inside a drained item keeps ordering FIFO.
    func drainPendingShellWorkBeforeMaterialization(for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        while let pending = pendingShellWorkBeforeMaterialization.removeValue(forKey: symbol) {
            for work in pending {
                work()
            }
        }
    }

    /// Runs everything queued by `deferUntilAfterImportedShellMaterializes`
    /// for `symbol`, after its record has been applied.
    func drainPendingShellWorkAfterMaterialization(for symbol: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        while let pending = pendingShellWorkAfterMaterialization.removeValue(forKey: symbol) {
            for work in pending {
                work()
            }
        }
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

    /// ARCH-031: deduplicated and sorted by source position so diagnostics
    /// rendering stays deterministic.
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

    public func reserveAdditionalSymbols(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        symbolsStorage.reserveCapacity(symbolsStorage.count + count)
        byFQName.reserveCapacity(byFQName.count + count)
        byShortName.reserveCapacity(byShortName.count + count / 2)
        byParentFQName.reserveCapacity(byParentFQName.count + count / 2)
    }

    public func lookup(fqName: [InternedString]) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        drainIndexedEntries(fqName: fqName)
        return byFQName[fqName]?.first
    }

    /// Like `lookup(fqName:)`, but prefers a nominal type symbol over a
    /// same-named function. `kotlin.collections.List` names both the `List`
    /// interface and the `List(size, init)` factory; picking the factory as a
    /// class symbol yields a type that is not a subtype of the real `List<T>`.
    public func lookupNominal(fqName: [InternedString]) -> SymbolID? {
        let candidates = lookupAll(fqName: fqName)
        return candidates.first(where: { id in
            switch symbol(id)?.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                true
            default:
                false
            }
        }) ?? candidates.first
    }

    public func lookupAll(fqName: [InternedString]) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        drainIndexedEntries(fqName: fqName)
        return byFQName[fqName] ?? []
    }

    public func lookupByShortName(_ name: InternedString) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        drainIndexedEntries(shortName: name)
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
        isContextProperty: Bool = false,
        topLevelFileID: FileID? = nil
    ) -> SymbolID {
        lock.lock()
        defer { lock.unlock() }

        // A define against an imported FQ name must see the pending index
        // entries first: shadowing and overload coexistence are decided
        // against the same symbol set eager registration produced. Package
        // synthesis stays with query paths so a claim arriving through the
        // children/short-name maps cannot order a package ahead of the
        // declaration this define is registering.
        drainIndexedEntries(fqName: fqName, synthesizePackage: false)

        if let existing = byFQName[fqName], !existing.isEmpty {
            // File-private callables in other files do not occupy this declaration's scope.
            let existingSymbols = existing.compactMap { symbol($0) }.filter { existing in
                guard let topLevelFileID else { return true }
                return !canCoexistAsFilePrivateTopLevelCallable(
                    kind: kind, visibility: visibility, fileID: topLevelFileID, existing: existing
                )
            }

            let sourceExistingSymbols = existingSymbols.filter {
                !$0.flags.contains(.importedLibrary)
            }
            let sourceCanShadowImportedLibrary = declSite != nil
                && !flags.contains(.synthetic)
                && !flags.contains(.importedLibrary)
                && existingSymbols.contains { $0.flags.contains(.importedLibrary) }
                && (
                    sourceExistingSymbols.isEmpty
                        || canCoexistAsOverload(
                            kind: kind,
                            existingSymbols: sourceExistingSymbols,
                            isExtensionProperty: isExtensionProperty,
                            isContextProperty: isContextProperty
                        )
                        || canCoexistAsExpectActual(
                            kind: kind,
                            flags: flags,
                            existingSymbols: sourceExistingSymbols
                        )
                        || canCoexistAsSyntheticPropertyFamily(
                            kind: kind,
                            flags: flags,
                            existingSymbols: sourceExistingSymbols
                        )
                )
            let shouldCoexist = sourceCanShadowImportedLibrary || canCoexistAsOverload(
                kind: kind,
                existingSymbols: existingSymbols,
                isExtensionProperty: isExtensionProperty,
                isContextProperty: isContextProperty
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
                    flags: flags,
                    prioritizeOverImported: sourceCanShadowImportedLibrary
                )
                if isExtensionProperty { declaredExtensionProperties.insert(id) }
                return id
            }
            // When a classifier coexists with a factory, a duplicate classifier
            // must reuse the classifier rather than the first (possibly callable) entry.
            // Parameters are likewise encoded as `ownerFQName + [paramName]`, so
            // a factory parameter can collide with an owner member at one FQName
            // (e.g. the `AtomicIntArray.size` property vs `fun AtomicIntArray(size:)`);
            // a duplicate parameter must reuse the first parameter symbol, not
            // that member — otherwise `setParentSymbol` reparents the member to
            // the factory function and member lookup loses it.
            if isNominalType(kind) || kind == .typeAlias
                || kind == .valueParameter || kind == .typeParameter,
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
        flags: SymbolFlags,
        prioritizeOverImported: Bool = false
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
        if prioritizeOverImported, var candidates = byFQName[fqName] {
            let importedIndex = candidates.firstIndex { candidate in
                symbolsStorage[Int(candidate.rawValue)].flags.contains(.importedLibrary)
            } ?? candidates.endIndex
            candidates.insert(id, at: importedIndex)
            byFQName[fqName] = candidates
        } else {
            byFQName[fqName, default: []].append(id)
        }
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
        isExtensionProperty: Bool = false,
        isContextProperty: Bool = false
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
                // are (e.g. `val Int.seconds` and `val Long.seconds`), and a
                // same-named top-level property occupies a separate lookup
                // path. Either kind of property can therefore coexist with
                // an extension property. Mirrors the diagnostic-level check
                // in HeaderHelpers.hasDeclarationConflict.
                return existingNonPackage.allSatisfy { existing in
                    isCallableLike(existing.kind)
                        || existing.kind == .property
                }
            }
            return existingNonPackage.allSatisfy { existing in
                isCallableLike(existing.kind)
                    || (existing.kind == .property
                        && (hasExtensionPropertyReceiver(existing.id)
                            || isContextProperty
                            || hasContextParameterProperty(existing)))
            }
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

    private func hasContextParameterProperty(_ property: SemanticSymbol) -> Bool {
        guard let getter = extensionPropertyGetterAccessors[property.id],
              let signature = functionSignatures[getter]
        else {
            return false
        }
        return !signature.contextParameterTypes.isEmpty
    }

    private func canCoexistAsExpectActual(
        kind: SymbolKind,
        flags: SymbolFlags,
        existingSymbols: [SemanticSymbol]
    ) -> Bool {
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
                // A `.static` synthetic helper shares a member FQName with a
                // user instance property without conflict — Kotlin generates
                // `Enum.entries` on the enum class even when a constructor
                // `val entries` exists, and member lookups keep declaration
                // order while static reads resolve the stub (KUU-3544).
                return symbol.flags.contains(.synthetic) || flags.contains(.static)
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

    public func valueParameterOwner(for symbol: SymbolID) -> SymbolID? {
        valueParameterOwners[symbol]
    }

    /// Returns only a signature already registered in this compilation. A nil
    /// result means unknown, not that an imported declaration has no signature.
    public func functionSignatureIfKnown(for symbol: SymbolID) -> FunctionSignature? {
        functionSignatures[symbol]
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

    func setInheritedDefaultsOwner(_ owner: SymbolID?, for implementation: SymbolID, receiver: TypeID) {
        inheritedDefaultsByReceiver[receiver, default: [:]][implementation] = owner
    }

    func inheritedDefaultsOwner(for implementation: SymbolID, receiver: TypeID) -> SymbolID? {
        inheritedDefaultsByReceiver[receiver]?[implementation]
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

    public func setPropertySetterVisibility(_ visibility: Visibility, for symbol: SymbolID) {
        propertySetterVisibilities[symbol] = visibility
    }

    public func propertySetterVisibility(for symbol: SymbolID) -> Visibility? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return propertySetterVisibilities[symbol]
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

    func markExtensionFunctionTypeSupertype(_ symbol: SymbolID) {
        extensionFunctionTypeSupertypeSymbols.insert(symbol)
    }

    func inheritsExtensionFunctionTypeSupertype(_ symbol: SymbolID) -> Bool {
        var visited: Set<SymbolID> = []
        var queue = [symbol]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            guard visited.insert(current).inserted else { continue }
            if extensionFunctionTypeSupertypeSymbols.contains(current) {
                return true
            }
            queue.append(contentsOf: directSupertypes(for: current))
        }
        return false
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

    private var classDelegationForwardingMethodReturnTypeSubstitutions: [SymbolID: (substitution: [TypeVarID: TypeID], typeVarBySymbol: [SymbolID: TypeVarID])] = [:]

    private var classDelegationForwardingMethodsByClass: [SymbolID: [SymbolID]] = [:]

    public func addClassDelegationForwardingMethod(
        _ forwardingSymbol: SymbolID,
        forClass classSymbol: SymbolID,
        interface interfaceSymbol: SymbolID,
        interfaceMethod interfaceMethodSymbol: SymbolID,
        field fieldSymbol: SymbolID,
        returnTypeSubstitution: [TypeVarID: TypeID] = [:],
        returnTypeTypeVarBySymbol: [SymbolID: TypeVarID] = [:]
    ) {
        classDelegationForwardingMethodInfo[forwardingSymbol] = (interfaceSymbol, interfaceMethodSymbol, fieldSymbol)
        classDelegationForwardingMethodReturnTypeSubstitutions[forwardingSymbol] = (
            returnTypeSubstitution,
            returnTypeTypeVarBySymbol
        )
        classDelegationForwardingMethodsByClass[classSymbol, default: []].append(forwardingSymbol)
    }

    public func classDelegationForwardingMethodSymbols(forClass classSymbol: SymbolID) -> [SymbolID] {
        classDelegationForwardingMethodsByClass[classSymbol] ?? []
    }

    public func classDelegationForwardingMethodInfo(for forwardingSymbol: SymbolID) -> (interfaceSymbol: SymbolID, interfaceMethodSymbol: SymbolID, fieldSymbol: SymbolID)? {
        classDelegationForwardingMethodInfo[forwardingSymbol]
    }

    func substitutedClassDelegationForwardingMethodReturnType(
        _ returnType: TypeID,
        for forwardingSymbol: SymbolID,
        types: TypeSystem
    ) -> TypeID? {
        guard let substitution = classDelegationForwardingMethodReturnTypeSubstitutions[forwardingSymbol] else {
            return nil
        }
        return types.substituteTypeParameters(
            in: returnType,
            substitution: substitution.substitution,
            typeVarBySymbol: substitution.typeVarBySymbol
        )
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
        lock.lock()
        defer { lock.unlock() }
        ensureLazyImportedMetadataLoaded(for: symbol)
        if nominalLayouts[symbol] == nil,
           indexedImportedNominals.contains(symbol),
           !lazyImportedMetadataLoadInProgress.contains(symbol),
           !importedLayoutSynthesisInProgress,
           let synthesizer = importedLayoutSynthesizer
        {
            importedLayoutSynthesisInProgress = true
            defer { importedLayoutSynthesisInProgress = false }
            synthesizer(symbol)
        }
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

    /// Import registration records compact-index link names before body decoding.
    /// This query never invokes the imported metadata loader.
    public func externalLinkNameIfKnown(for symbol: SymbolID) -> String? {
        externalLinkNames[symbol]
    }

    public func externalLinkName(for symbol: SymbolID) -> String? {
        ensureLazyImportedMetadataLoaded(for: symbol)
        return externalLinkNames[symbol]
    }

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
        lock.lock()
        defer { lock.unlock() }
        if let previous = parentSymbols[child], previous != parent {
            childrenByParent[previous]?.remove(child)
        }
        parentSymbols[child] = parent
        childrenByParent[parent, default: []].insert(child)
    }

    /// Returns registered ownership without decoding imported metadata. Lazy
    /// shells register compact-index ownership after all owners are defined.
    public func parentSymbolIfKnown(for child: SymbolID) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return parentSymbols[child]
    }

    /// Returns direct children owned by this exact symbol in declaration order.
    /// FQName-only lookup may combine members from source and imported
    /// declarations that share a name.
    public func children(of parent: SymbolID) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        if let parentInfo = symbol(parent) {
            drainIndexedChildren(parentFQName: parentInfo.fqName)
        }
        return (childrenByParent[parent] ?? []).sorted { $0.rawValue < $1.rawValue }
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

    /// Reverse of `backingFieldSymbol(for:)`, built from the (sparse) backing
    /// field table rather than by scanning every symbol.
    func propertiesByBackingFieldSymbol() -> [SymbolID: SymbolID] {
        var result: [SymbolID: SymbolID] = [:]
        result.reserveCapacity(backingFieldSymbols.count)
        for (property, backingField) in backingFieldSymbols {
            result[backingField] = property
        }
        return result
    }

    public func setDelegateStorageSymbol(_ storage: SymbolID, for property: SymbolID) {
        if let previousStorage = delegateStorageSymbols[property], previousStorage != storage {
            delegatePropertiesByStorageSymbol.removeValue(forKey: previousStorage)
        }
        delegateStorageSymbols[property] = storage
        delegatePropertiesByStorageSymbol[storage] = property
    }

    public func delegateStorageSymbol(for property: SymbolID) -> SymbolID? {
        delegateStorageSymbols[property]
    }

    public func delegateProperty(forStorageSymbol storage: SymbolID) -> SymbolID? {
        delegatePropertiesByStorageSymbol[storage]
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

    /// Compact-index registration fact: the record carries a receiver
    /// signature, so body decoding will restore an extension receiver.
    /// `hasExtensionPropertyReceiver` answers from this without loading it.
    public func markImportedExtensionReceiverProperty(_ property: SymbolID) {
        importedExtensionReceiverProperties.insert(property)
    }

    public func hasExtensionPropertyReceiver(_ property: SymbolID) -> Bool {
        declaredExtensionProperties.contains(property)
            || extensionPropertyReceiverTypes[property] != nil
            || importedExtensionReceiverProperties.contains(property)
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

    func markImportedStdlibSymbol(_ symbol: SymbolID) {
        importedStdlibSymbolIDs.insert(symbol)
    }

    func isImportedStdlibSymbol(_ symbol: SymbolID) -> Bool {
        importedStdlibSymbolIDs.contains(symbol)
    }

    func markImportedRuntimeReflectionMetadata(_ scope: String, for symbol: SymbolID) {
        guard scope == "public" || scope == "all" else { return }
        importedRuntimeReflectionScopes[symbol] = scope
    }

    func hasImportedRuntimeReflectionMetadata(for symbol: SymbolID) -> Bool {
        guard let scope = importedRuntimeReflectionScopes[symbol] else { return false }
        if scope == "all" { return true }
        guard let imported = self.symbol(symbol) else { return false }
        return imported.visibility == .public || imported.visibility == .protected
    }

    public func setSourceFileID(_ fileID: FileID, for symbol: SymbolID) {
        sourceFileIDs[symbol] = fileID
    }

    public func sourceFileID(for symbol: SymbolID) -> FileID? {
        sourceFileIDs[symbol]
    }

    public func setModuleFQN(_ moduleFQN: InternedString, for symbol: SymbolID) {
        guard moduleFQNames[symbol] != moduleFQN else { return }
        if let previousModule = moduleFQNames[symbol] {
            byModuleFQN[previousModule]?.removeAll { $0 == symbol }
        }
        moduleFQNames[symbol] = moduleFQN
        byModuleFQN[moduleFQN, default: []].append(symbol)
    }

    public func moduleFQN(for symbol: SymbolID) -> InternedString? {
        moduleFQNames[symbol]
    }

    /// Returns module members in assignment order without forcing imported metadata.
    public func symbols(inModule moduleFQN: InternedString) -> [SymbolID] {
        byModuleFQN[moduleFQN] ?? []
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

    /// Companion edges are restored from the compact index at shell
    /// registration; this read never invokes the imported metadata loader.
    public func companionObjectSymbolIfKnown(for owner: SymbolID) -> SymbolID? {
        companionObjectSymbols[owner]
    }

    /// Returns the hidden implementation object used to scope companion-block
    /// declarations. It is intentionally distinct from a source companion
    /// object because Kotlin exposes the two through different qualifiers.
    public func companionBlockObjectSymbol(
        for owner: SymbolID,
        interner: StringInterner
    ) -> SymbolID? {
        let implementationOwner = actualSymbol(for: owner) ?? owner
        guard let ownerInfo = symbol(implementationOwner) else { return nil }
        let blockName = interner.intern("$CompanionBlocks")
        return lookupAll(fqName: ownerInfo.fqName + [blockName]).first { candidate in
            parentSymbol(for: candidate) == implementationOwner
                && symbol(candidate)?.kind == .object
        }
    }

    public func setOuterInstanceFieldSymbol(_ field: SymbolID, for innerClass: SymbolID) {
        outerInstanceFieldSymbols[innerClass] = field
    }

    public func outerInstanceFieldSymbol(for innerClass: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: innerClass)
        return outerInstanceFieldSymbols[innerClass]
    }

    public func setObjectInitializerSymbol(_ initializer: SymbolID, for object: SymbolID) {
        objectInitializerSymbols[object] = initializer
    }

    public func objectInitializerSymbol(for object: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: object)
        return objectInitializerSymbols[object]
    }

    /// Initializer shells are synthesized from compact-index link names at
    /// shell registration, so this read never invokes the metadata loader.
    public func objectInitializerSymbolIfKnown(for object: SymbolID) -> SymbolID? {
        objectInitializerSymbols[object]
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

    /// Initializer shells are synthesized from compact-index link names at
    /// shell registration, so this read never invokes the metadata loader.
    public func companionObjectInitializerSymbolIfKnown(for owner: SymbolID) -> SymbolID? {
        companionObjectInitializerSymbols[owner]
    }

    public func setEnumStaticInitSymbol(_ initializer: SymbolID, for owner: SymbolID) {
        enumStaticInitSymbols[owner] = initializer
    }

    public func enumStaticInitSymbol(for owner: SymbolID) -> SymbolID? {
        ensureLazyImportedMetadataLoaded(for: owner)
        return enumStaticInitSymbols[owner]
    }

    /// Initializer shells are synthesized from compact-index link names at
    /// shell registration, so this read never invokes the metadata loader.
    public func enumStaticInitSymbolIfKnown(for owner: SymbolID) -> SymbolID? {
        enumStaticInitSymbols[owner]
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

    public func setHasProvideDelegate(for property: SymbolID) {
        delegateHasProvideDelegate.insert(property)
    }

    public func hasProvideDelegate(for property: SymbolID) -> Bool {
        delegateHasProvideDelegate.contains(property)
    }

    public func setExpectActualLink(expect: SymbolID, actual: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        expectActualLinks[expect] = actual
        if functionSignatures[expect]?.valueParameterHasDefaultValues.contains(true) == true {
            expectActualDefaultArgumentOwners[actual] = expect
        }
    }

    public func actualSymbol(for expect: SymbolID) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return expectActualLinks[expect]
    }

    public func expectActualDefaultArgumentOwner(for actual: SymbolID) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return expectActualDefaultArgumentOwners[actual]
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

    public func addContractCallsInPlaceEffect(_ effect: ContractCallsInPlaceEffect, for function: SymbolID) {
        var effects = contractCallsInPlaceEffects[function] ?? []
        if !effects.contains(effect) { effects.append(effect) }
        contractCallsInPlaceEffects[function] = effects
    }

    public func contractCallsInPlaceEffects(for function: SymbolID) -> [ContractCallsInPlaceEffect] {
        contractCallsInPlaceEffects[function] ?? []
    }

    public func setContractReturnsNotNull(for function: SymbolID) {
        contractReturnsNotNullEffects.insert(function)
    }

    public func setContractConditionEffect(_ effect: ContractConditionEffect, for function: SymbolID) {
        contractConditionEffects[function] = effect
    }

    public func contractConditionEffect(for function: SymbolID) -> ContractConditionEffect? {
        contractConditionEffects[function]
    }

    public func symbols(ofKind kind: SymbolKind) -> [SymbolID] {
        byKind[kind] ?? []
    }

    public func children(ofFQName parentFQName: [InternedString]) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        drainIndexedChildren(parentFQName: parentFQName)
        return byParentFQName[parentFQName] ?? []
    }

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

    /// Returns true for a compiler-registered synthetic stub with no compiled
    /// body. A precomputed stdlib artifact serializes these stubs instead of
    /// letting the consumer register them again (KUU-2815), and every imported
    /// record carries `.synthetic`, so the imported copy of a stub is the
    /// stdlib record that has no compiled link name.
    public func isSyntheticStubSymbol(_ symbolID: SymbolID) -> Bool {
        guard let symbol = self.symbol(symbolID),
              symbol.flags.contains(.synthetic)
        else { return false }
        guard symbol.flags.contains(.importedLibrary) else { return true }
        return isImportedStdlibSymbol(symbolID)
            && (externalLinkName(for: symbolID)?.isEmpty ?? true)
    }
}

extension SymbolTable {
    func makeSemaSnapshot(interner: StringInterner) -> SymbolTableSemaSnapshot {
        SymbolTableSemaSnapshot(
            symbols: symbolsStorage.map { symbol in
                SemaSnapshotSymbol(
                    id: symbol.id,
                    kind: symbol.kind,
                    name: interner.resolve(symbol.name),
                    fqName: symbol.fqName.map(interner.resolve),
                    visibility: symbol.visibility,
                    flags: symbol.flags
                )
            },
            functionSignatures: functionSignatures,
            propertyTypes: propertyTypes,
            propertyHasCustomGetter: propertyHasCustomGetter,
            propertySetterVisibilities: propertySetterVisibilities,
            directSupertypes: directSupertypes,
            supertypeTypeArgsMap: supertypeTypeArgsMap,
            extensionFunctionTypeSupertypeSymbols: extensionFunctionTypeSupertypeSymbols,
            nominalLayouts: nominalLayouts,
            nominalLayoutHints: nominalLayoutHints,
            externalLinkNames: externalLinkNames,
            functionABIReturnTypes: functionABIReturnTypes,
            stdlibSpecialCallKindsBySymbol: stdlibSpecialCallKindsBySymbol,
            typeAliasUnderlyingTypes: typeAliasUnderlyingTypes,
            typeAliasTypeParameters: typeAliasTypeParameters,
            parentSymbols: parentSymbols,
            backingFieldSymbols: backingFieldSymbols,
            delegateStorageSymbols: delegateStorageSymbols,
            delegatePropertiesByStorageSymbol: delegatePropertiesByStorageSymbol,
            delegateGetValueSymbols: delegateGetValueSymbols,
            delegateSetValueSymbols: delegateSetValueSymbols,
            delegateProvideDelegateSymbols: delegateProvideDelegateSymbols,
            accessorOwnerProperties: accessorOwnerProperties,
            extensionPropertyReceiverTypes: extensionPropertyReceiverTypes,
            importedExtensionReceiverProperties: importedExtensionReceiverProperties,
            declaredExtensionProperties: declaredExtensionProperties,
            extensionPropertyGetterAccessors: extensionPropertyGetterAccessors,
            extensionPropertySetterAccessors: extensionPropertySetterAccessors,
            typeParameterUpperBoundsMap: typeParameterUpperBoundsMap,
            importedStdlibSymbolIDs: importedStdlibSymbolIDs,
            moduleFQNames: moduleFQNames.mapValues(interner.resolve),
            annotationsStorage: annotationsStorage,
            companionObjectSymbols: companionObjectSymbols,
            outerInstanceFieldSymbols: outerInstanceFieldSymbols,
            objectInitializerSymbols: objectInitializerSymbols,
            objectLazyInitializerSymbols: objectLazyInitializerSymbols,
            companionObjectInitializerSymbols: companionObjectInitializerSymbols,
            enumStaticInitSymbols: enumStaticInitSymbols,
            enumEntryDispatchTargets: enumEntryDispatchTargets,
            enumEntryDispatchBaseSymbols: enumEntryDispatchBaseSymbols,
            valueClassUnderlyingTypes: valueClassUnderlyingTypes,
            sealedSubclassesStorage: sealedSubclassesStorage,
            constValueExprKinds: constValueExprKinds.mapValues { SemaSnapshotConstValue($0, interner: interner) },
            delegateHasProvideDelegate: delegateHasProvideDelegate,
            expectActualLinks: expectActualLinks,
            expectActualDefaultArgumentOwners: expectActualDefaultArgumentOwners,
            contractNonNullEffects: contractNonNullEffects,
            contractImplicationEffects: contractImplicationEffects,
            contractReturnsEffects: contractReturnsEffects,
            contractCallsInPlaceEffects: contractCallsInPlaceEffects,
            contractReturnsNotNullEffects: contractReturnsNotNullEffects,
            contractConditionEffects: contractConditionEffects,
            importedNominalsWithoutInitializers: importedNominalsWithoutInitializers,
            importedNominalsWithIncompleteInitializerInfo: importedNominalsWithIncompleteInitializerInfo,
            importedMemberIndexShapes: importedMemberIndexShapes.mapValues { shape in
                SemaSnapshotMemberIndexShape(
                    arity: shape.arity,
                    receiverOwnerFQName: shape.receiverOwnerFQName?.map(interner.resolve),
                    hasDefaultArguments: shape.hasDefaultArguments
                )
            },
            delegatedInterfacesByClass: delegatedInterfacesByClass,
            klibDefinedGlobalSymbols: klibDefinedGlobalSymbols,
            overrideDefaultsBaseSymbols: overrideDefaultsBaseSymbols,
            inheritedDefaultsByReceiver: inheritedDefaultsByReceiver
        )
    }

    func registerSemaSnapshotSymbols(
        _ snapshot: SymbolTableSemaSnapshot,
        interner: StringInterner
    ) -> [SymbolID: SymbolID] {
        var symbolMap: [SymbolID: SymbolID] = [:]
        symbolMap.reserveCapacity(snapshot.symbols.count * 2)
        reserveAdditionalSymbols(snapshot.symbols.count)
        for entry in snapshot.symbols.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let fqName = entry.fqName.map(interner.intern)
            let name = interner.intern(entry.name)
            let isExtensionProperty = snapshot.importedExtensionReceiverProperties.contains(entry.id)
                || snapshot.declaredExtensionProperties.contains(entry.id)
            let existing = (byFQName[fqName] ?? []).compactMap(symbol)
            let matchingPackage = entry.kind == .package
                ? existing.first(where: { $0.kind == .package })?.id
                : nil
            let matchingLinkedSymbol: SymbolID? = snapshot.externalLinkNames[entry.id].flatMap { linkName in
                existing.first(where: {
                    $0.kind == entry.kind
                        && $0.name == name
                        && $0.visibility == entry.visibility
                        && $0.flags == entry.flags
                        && externalLinkNames[$0.id] == linkName
                })?.id
            }
            let restored = matchingPackage ?? matchingLinkedSymbol ?? define(
                kind: entry.kind,
                name: name,
                fqName: fqName,
                declSite: nil,
                visibility: entry.visibility,
                flags: entry.flags,
                isExtensionProperty: isExtensionProperty
            )
            symbolMap[entry.id] = restored
            if snapshot.importedExtensionReceiverProperties.contains(entry.id) {
                markImportedExtensionReceiverProperty(restored)
            }
        }
        let baseMappings = Array(symbolMap)
        for (old, new) in baseMappings where old.rawValue >= 0 {
            symbolMap[SyntheticSymbolScheme.defaultStubSymbol(for: old)] = SyntheticSymbolScheme.defaultStubSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.defaultMaskSymbol(for: old)] = SyntheticSymbolScheme.defaultMaskSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.setterValueParameterSymbol(for: old)] = SyntheticSymbolScheme.setterValueParameterSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.semaSetterValueSymbol(for: old)] = SyntheticSymbolScheme.semaSetterValueSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.receiverParameterSymbol(for: old)] = SyntheticSymbolScheme.receiverParameterSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: old)] = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.propertySetterAccessorSymbol(for: old)] = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: old)] = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: new)
            symbolMap[SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: old)] = SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: new)
        }
        for (old, new) in baseMappings where old.rawValue >= 0 {
            for index in 0 ..< 3 {
                let oldDerived = SyntheticSymbolScheme.delegateLambdaParameterSymbol(for: old, at: index)
                let newDerived = SyntheticSymbolScheme.delegateLambdaParameterSymbol(for: new, at: index)
                symbolMap[oldDerived] = newDerived
            }
        }
        return symbolMap
    }

    func restoreSemaSnapshotState(
        _ snapshot: SymbolTableSemaSnapshot,
        symbolMap: [SymbolID: SymbolID],
        typeMap: [TypeID: TypeID],
        interner: StringInterner
    ) {

        func mapSymbol(_ symbol: SymbolID) -> SymbolID { symbolMap[symbol] ?? symbol }
        func mapSymbols(_ symbols: [SymbolID]) -> [SymbolID] { symbols.map(mapSymbol) }
        func mapType(_ type: TypeID, using typeMap: [TypeID: TypeID]) -> TypeID { typeMap[type] ?? type }
        func mapArgs(_ args: [TypeArg], using typeMap: [TypeID: TypeID]) -> [TypeArg] {
            args.map { $0.mapTypes { mapType($0, using: typeMap) } }
        }
        func mapSignature(_ signature: FunctionSignature, using typeMap: [TypeID: TypeID]) -> FunctionSignature {
            FunctionSignature(
                receiverType: signature.receiverType.map { mapType($0, using: typeMap) },
                contextReceiverTypes: signature.contextReceiverTypes.map { mapType($0, using: typeMap) },
                contextParameterSymbols: mapSymbols(signature.contextParameterSymbols),
                contextParameterTypes: signature.contextParameterTypes.map { mapType($0, using: typeMap) },
                parameterTypes: signature.parameterTypes.map { mapType($0, using: typeMap) },
                returnType: mapType(signature.returnType, using: typeMap),
                isSuspend: signature.isSuspend,
                canThrow: signature.canThrow,
                valueParameterSymbols: mapSymbols(signature.valueParameterSymbols),
                valueParameterUnsafeVarianceTypeParameterSymbols: signature.valueParameterUnsafeVarianceTypeParameterSymbols.map { Set(mapSymbols(Array($0))) },
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                hasStableParameterNames: signature.hasStableParameterNames,
                typeParameterSymbols: mapSymbols(signature.typeParameterSymbols),
                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: signature.typeParameterUpperBounds.map { $0.map { mapType($0, using: typeMap) } },
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList.map { $0.map { mapType($0, using: typeMap) } },
                classTypeParameterCount: signature.classTypeParameterCount
            )
        }
        func mapContractImplication(_ effect: ContractImplicationEffect, using typeMap: [TypeID: TypeID]) -> ContractImplicationEffect {
            ContractImplicationEffect(
                target: effect.target,
                returnCondition: effect.returnCondition,
                argumentCondition: effect.argumentCondition,
                targetType: effect.targetType.map { mapType($0, using: typeMap) },
                targetTypeSignature: effect.targetTypeSignature
            )
        }
        func mapLayout(_ layout: NominalLayout) -> NominalLayout {
            func mapOffsets(_ source: [SymbolID: Int]) -> [SymbolID: Int] {
                var result: [SymbolID: Int] = [:]
                for key in source.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                    result[mapSymbol(key)] = source[key]
                }
                return result
            }
            return NominalLayout(
                objectHeaderWords: layout.objectHeaderWords,
                instanceFieldCount: layout.instanceFieldCount,
                instanceSizeWords: layout.instanceSizeWords,
                fieldOffsets: mapOffsets(layout.fieldOffsets),
                vtableSlots: mapOffsets(layout.vtableSlots),
                itableSlots: mapOffsets(layout.itableSlots),
                vtableSize: layout.vtableSize,
                itableSize: layout.itableSize,
                superClass: layout.superClass.map(mapSymbol)
            )
        }

        for (symbol, signature) in snapshot.functionSignatures {
            let id = mapSymbol(symbol)
            let mapped = mapSignature(signature, using: typeMap)
            functionSignatures[id] = mapped
            for parameter in mapped.valueParameterSymbols where valueParameterOwners[parameter] == nil {
                valueParameterOwners[parameter] = id
            }
        }
        for (symbol, type) in snapshot.propertyTypes { propertyTypes[mapSymbol(symbol)] = mapType(type, using: typeMap) }
        for (symbol, value) in snapshot.propertyHasCustomGetter { propertyHasCustomGetter[mapSymbol(symbol)] = value }
        for (symbol, visibility) in snapshot.propertySetterVisibilities { propertySetterVisibilities[mapSymbol(symbol)] = visibility }
        for (symbol, supertypes) in snapshot.directSupertypes {
            let mappedSymbol = mapSymbol(symbol)
            let mappedSupertypes = mapSymbols(supertypes)
            directSupertypes[mappedSymbol] = mappedSupertypes
            for supertype in mappedSupertypes where directSubtypesIndex[supertype]?.contains(mappedSymbol) != true {
                directSubtypesIndex[supertype, default: []].append(mappedSymbol)
            }
        }
        for (child, parents) in snapshot.supertypeTypeArgsMap {
            let mappedChild = mapSymbol(child)
            for (parent, args) in parents {
                supertypeTypeArgsMap[mappedChild, default: [:]][mapSymbol(parent)] = mapArgs(args, using: typeMap)
            }
        }
        for symbol in snapshot.extensionFunctionTypeSupertypeSymbols ?? [] {
            extensionFunctionTypeSupertypeSymbols.insert(mapSymbol(symbol))
        }
        for (symbol, layout) in snapshot.nominalLayouts { nominalLayouts[mapSymbol(symbol)] = mapLayout(layout) }
        for (symbol, hint) in snapshot.nominalLayoutHints { nominalLayoutHints[mapSymbol(symbol)] = hint }
        for (symbol, name) in snapshot.externalLinkNames { externalLinkNames[mapSymbol(symbol)] = name }
        for (symbol, type) in snapshot.functionABIReturnTypes { functionABIReturnTypes[mapSymbol(symbol)] = mapType(type, using: typeMap) }
        for (symbol, kind) in snapshot.stdlibSpecialCallKindsBySymbol { stdlibSpecialCallKindsBySymbol[mapSymbol(symbol)] = kind }
        for (symbol, type) in snapshot.typeAliasUnderlyingTypes { typeAliasUnderlyingTypes[mapSymbol(symbol)] = mapType(type, using: typeMap) }
        for (symbol, parameters) in snapshot.typeAliasTypeParameters { typeAliasTypeParameters[mapSymbol(symbol)] = mapSymbols(parameters) }
        for (child, parent) in snapshot.parentSymbols {
            let mappedChild = mapSymbol(child)
            let mappedParent = mapSymbol(parent)
            parentSymbols[mappedChild] = mappedParent
            childrenByParent[mappedParent, default: []].insert(mappedChild)
        }
        for (symbol, backing) in snapshot.backingFieldSymbols { backingFieldSymbols[mapSymbol(symbol)] = mapSymbol(backing) }
        for (symbol, storage) in snapshot.delegateStorageSymbols { delegateStorageSymbols[mapSymbol(symbol)] = mapSymbol(storage) }
        for (storage, property) in snapshot.delegatePropertiesByStorageSymbol { delegatePropertiesByStorageSymbol[mapSymbol(storage)] = mapSymbol(property) }
        for (symbol, getter) in snapshot.delegateGetValueSymbols { delegateGetValueSymbols[mapSymbol(symbol)] = mapSymbol(getter) }
        for (symbol, setter) in snapshot.delegateSetValueSymbols { delegateSetValueSymbols[mapSymbol(symbol)] = mapSymbol(setter) }
        for (symbol, provider) in snapshot.delegateProvideDelegateSymbols { delegateProvideDelegateSymbols[mapSymbol(symbol)] = mapSymbol(provider) }
        for (accessor, property) in snapshot.accessorOwnerProperties { accessorOwnerProperties[mapSymbol(accessor)] = mapSymbol(property) }
        for (symbol, type) in snapshot.extensionPropertyReceiverTypes { extensionPropertyReceiverTypes[mapSymbol(symbol)] = mapType(type, using: typeMap) }
        importedExtensionReceiverProperties.formUnion(snapshot.importedExtensionReceiverProperties.map(mapSymbol))
        for symbol in snapshot.declaredExtensionProperties { declaredExtensionProperties.insert(mapSymbol(symbol)) }
        for (property, accessor) in snapshot.extensionPropertyGetterAccessors { extensionPropertyGetterAccessors[mapSymbol(property)] = mapSymbol(accessor) }
        for (property, accessor) in snapshot.extensionPropertySetterAccessors { extensionPropertySetterAccessors[mapSymbol(property)] = mapSymbol(accessor) }
        for (symbol, bounds) in snapshot.typeParameterUpperBoundsMap { typeParameterUpperBoundsMap[mapSymbol(symbol)] = bounds.map { mapType($0, using: typeMap) } }
        importedStdlibSymbolIDs.formUnion(snapshot.importedStdlibSymbolIDs.map(mapSymbol))
        var moduleFQNSymbols = byModuleFQN.mapValues { Set($0) }
        for (symbol, module) in snapshot.moduleFQNames {
            let id = mapSymbol(symbol)
            let moduleID = interner.intern(module)
            moduleFQNames[id] = moduleID
            // Snapshot restoration can add thousands of symbols to one module;
            // keep duplicate checks constant-time instead of rescanning its array.
            if moduleFQNSymbols[moduleID, default: []].insert(id).inserted {
                byModuleFQN[moduleID, default: []].append(id)
            }
        }
        for (symbol, annotations) in snapshot.annotationsStorage {
            annotationsStorage[mapSymbol(symbol)] = annotations.map { annotation in
                MetadataAnnotationRecord(
                    annotationFQName: annotation.annotationFQName,
                    arguments: annotation.arguments,
                    useSiteTarget: annotation.useSiteTarget,
                    retention: annotation.retention,
                    usageID: annotation.usageID,
                    factorySymbol: annotation.factorySymbol.map(mapSymbol),
                    factoryLinkName: annotation.factoryLinkName
                )
            }
        }
        for (owner, companion) in snapshot.companionObjectSymbols { companionObjectSymbols[mapSymbol(owner)] = mapSymbol(companion) }
        for (symbol, field) in snapshot.outerInstanceFieldSymbols { outerInstanceFieldSymbols[mapSymbol(symbol)] = mapSymbol(field) }
        for (symbol, initializer) in snapshot.objectInitializerSymbols { objectInitializerSymbols[mapSymbol(symbol)] = mapSymbol(initializer) }
        for (symbol, initializer) in snapshot.objectLazyInitializerSymbols { objectLazyInitializerSymbols[mapSymbol(symbol)] = mapSymbol(initializer) }
        for (symbol, initializer) in snapshot.companionObjectInitializerSymbols { companionObjectInitializerSymbols[mapSymbol(symbol)] = mapSymbol(initializer) }
        for (symbol, initializer) in snapshot.enumStaticInitSymbols { enumStaticInitSymbols[mapSymbol(symbol)] = mapSymbol(initializer) }
        for (symbol, targets) in snapshot.enumEntryDispatchTargets {
            enumEntryDispatchTargets[mapSymbol(symbol)] = targets.map { EnumEntryDispatchTarget(entrySymbol: mapSymbol($0.entrySymbol), functionSymbol: mapSymbol($0.functionSymbol)) }
        }
        for (symbol, base) in snapshot.enumEntryDispatchBaseSymbols { enumEntryDispatchBaseSymbols[mapSymbol(symbol)] = mapSymbol(base) }
        for (symbol, type) in snapshot.valueClassUnderlyingTypes { valueClassUnderlyingTypes[mapSymbol(symbol)] = mapType(type, using: typeMap) }
        for (symbol, subclasses) in snapshot.sealedSubclassesStorage { sealedSubclassesStorage[mapSymbol(symbol)] = mapSymbols(subclasses) }
        for (symbol, value) in snapshot.constValueExprKinds { constValueExprKinds[mapSymbol(symbol)] = value.materialize(interner: interner, mapSymbol: mapSymbol) }
        delegateHasProvideDelegate.formUnion(snapshot.delegateHasProvideDelegate.map(mapSymbol))
        for (expect, actual) in snapshot.expectActualLinks { expectActualLinks[mapSymbol(expect)] = mapSymbol(actual) }
        for (actual, owner) in snapshot.expectActualDefaultArgumentOwners { expectActualDefaultArgumentOwners[mapSymbol(actual)] = mapSymbol(owner) }
        for (symbol, effect) in snapshot.contractNonNullEffects {
            contractNonNullEffects[mapSymbol(symbol)] = ContractNonNullEffect(parameterSymbol: mapSymbol(effect.parameterSymbol), appliesOnAnyReturn: effect.appliesOnAnyReturn)
        }
        for (symbol, effects) in snapshot.contractImplicationEffects { contractImplicationEffects[mapSymbol(symbol)] = effects.map { mapContractImplication($0, using: typeMap) } }
        for (symbol, effect) in snapshot.contractReturnsEffects { contractReturnsEffects[mapSymbol(symbol)] = effect }
        for (symbol, effects) in snapshot.contractCallsInPlaceEffects {
            contractCallsInPlaceEffects[mapSymbol(symbol)] = effects.map { ContractCallsInPlaceEffect(parameterSymbol: mapSymbol($0.parameterSymbol), kind: $0.kind) }
        }
        contractReturnsNotNullEffects.formUnion(snapshot.contractReturnsNotNullEffects.map(mapSymbol))
        for (symbol, effect) in snapshot.contractConditionEffects { contractConditionEffects[mapSymbol(symbol)] = effect }
        importedNominalsWithoutInitializers.formUnion(snapshot.importedNominalsWithoutInitializers.map(mapSymbol))
        importedNominalsWithIncompleteInitializerInfo.formUnion(snapshot.importedNominalsWithIncompleteInitializerInfo.map(mapSymbol))
        for (symbol, shape) in snapshot.importedMemberIndexShapes {
            let receiver = shape.receiverOwnerFQName?.map(interner.intern)
            importedMemberIndexShapes[mapSymbol(symbol)] = ImportedMemberIndexShape(arity: shape.arity, receiverOwnerFQName: receiver, hasDefaultArguments: shape.hasDefaultArguments)
        }
        for (classSymbol, interfaces) in snapshot.delegatedInterfacesByClass {
            delegatedInterfacesByClass[mapSymbol(classSymbol), default: []].formUnion(interfaces.map(mapSymbol))
        }
        klibDefinedGlobalSymbols.formUnion(snapshot.klibDefinedGlobalSymbols.map(mapSymbol))
        for (symbol, base) in snapshot.overrideDefaultsBaseSymbols { overrideDefaultsBaseSymbols[mapSymbol(symbol)] = mapSymbol(base) }
        for (receiver, defaults) in snapshot.inheritedDefaultsByReceiver {
            let mappedReceiver = mapType(receiver, using: typeMap)
            for (implementation, owner) in defaults {
                inheritedDefaultsByReceiver[mappedReceiver, default: [:]][mapSymbol(implementation)] = mapSymbol(owner)
            }
        }
    }
}
