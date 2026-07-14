import Foundation

/// Key for a bundled stdlib member declaration. The same shape is used by
/// KSP-002 skip guards and KSP-003 duplicate-definition warnings.
struct BundledMemberKey: Hashable, Sendable {
    let ownerFQName: [InternedString]
    let name: InternedString
    let arity: Int
}

/// Index of member declarations originating from bundled stdlib virtual sources (`__bundled_*.kt`).
struct BundledDeclarationIndex: Sendable {
    static let empty = BundledDeclarationIndex(keys: [])

    private let keys: Set<BundledMemberKey>

    init(keys: Set<BundledMemberKey> = []) {
        self.keys = keys
    }

    func contains(_ key: BundledMemberKey) -> Bool {
        keys.contains(key)
    }

    func contains(owner: [InternedString], name: InternedString, arity: Int) -> Bool {
        contains(BundledMemberKey(ownerFQName: owner, name: name, arity: arity))
    }

    func contains(ownerFQName: [InternedString], name: InternedString, arity: Int) -> Bool {
        contains(owner: ownerFQName, name: name, arity: arity)
    }

    mutating func insert(_ key: BundledMemberKey) {
        self = BundledDeclarationIndex(keys: keys.union([key]))
    }

    /// Build from AST bundled sources before SymbolTable header collection.
    /// AST scanning preserves the current phase order while supplying
    /// `(owner, name, arity)` keys to synthetic stub registration.
    static func build(ast: ASTModule, sourceManager: SourceManager, interner: StringInterner) -> BundledDeclarationIndex {
        BundledDeclarationIndex(keys: buildKeys(ast: ast, sourceManager: sourceManager, interner: interner))
    }

    static func build(
        ast: ASTModule,
        symbols _: SymbolTable,
        types _: TypeSystem,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> BundledDeclarationIndex {
        var keys = buildKeys(ast: ast, sourceManager: sourceManager, interner: interner)
        addListIterableAliases(to: &keys, interner: interner)
        return BundledDeclarationIndex(keys: keys)
    }

    /// Build from SymbolTable symbols whose `declSite` is in bundled virtual files.
    static func build(sourceManager: SourceManager, symbols: SymbolTable, types: TypeSystem) -> BundledDeclarationIndex {
        buildFromSymbols(
            symbols: symbols,
            types: types,
            sourceManager: sourceManager,
            interner: nil
        )
    }

    /// Build from bundled SymbolTable declarations after bundled header collection.
    static func build(
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> BundledDeclarationIndex {
        buildFromSymbols(
            symbols: symbols,
            types: types,
            sourceManager: sourceManager,
            interner: interner
        )
    }

    static func memberKey(
        for symbol: SemanticSymbol,
        symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> BundledMemberKey? {
        makeMemberKey(
            for: symbol,
            symbolID: symbolID,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    static func ownerFQName(
        declaredOwnerFQName: [InternedString],
        receiverType: TypeID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [InternedString] {
        ownerFQName(
            declaredOwnerFQName: declaredOwnerFQName,
            receiverType: receiverType,
            symbols: symbols,
            types: types,
            interner: Optional(interner)
        ) ?? declaredOwnerFQName
    }

    func warnSyntheticOverlaps(
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        var reported: Set<BundledMemberKey> = []
        for symbol in symbols.allSymbols() {
            guard symbol.flags.contains(.synthetic) else { continue }
            guard symbol.kind == .function || symbol.kind == .property else { continue }
            guard let key = Self.memberKey(
                for: symbol,
                symbolID: symbol.id,
                symbols: symbols,
                types: types,
                interner: interner
            )
            else { continue }
            guard !Self.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner) else {
                continue
            }
            guard contains(key), reported.insert(key).inserted else { continue }

            let ownerDisplay = key.ownerFQName.map { interner.resolve($0) }.joined(separator: ".")
            let memberDisplay = interner.resolve(key.name)
            diagnostics.warning(
                "KSWIFTK-SEMA-0102",
                "Synthetic stub '\(memberDisplay)' on '\(ownerDisplay)' (arity \(key.arity)) duplicates bundled stdlib declaration; KSP-002 skip guard missed.",
                range: nil
            )
        }
    }

    static func isRuntimeBackedSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        let ownerFQName = key.ownerFQName.map { interner.resolve($0) }
        if ownerFQName == ["kotlin", "collections", "List"] {
            return isRuntimeBackedListSyntheticRetainedOverlap(key, interner: interner)
        }
        if ownerFQName == ["kotlin", "collections", "Iterable"] {
            return isRuntimeBackedIterableSyntheticRetainedOverlap(key, interner: interner)
        }
        if ownerFQName == ["kotlin", "sequences", "Sequence"] {
            return isRuntimeBackedSequenceSyntheticRetainedOverlap(key, interner: interner)
        }
        if isRuntimeBackedAtomicSyntheticRetainedOverlap(key, ownerFQName: ownerFQName, interner: interner) {
            return true
        }
        if ownerFQName == ["kotlin", "random", "Random"] {
            return isRuntimeBackedRandomSyntheticRetainedOverlap(key, interner: interner)
        }
        return false
    }

    private static func isRuntimeBackedRandomSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        // KSP-466/KSP-457: nextInt(range: IntRange)/nextLong(range: LongRange)/
        // nextUInt(range: UIntRange)/nextULong(range: ULongRange) stay native
        // bridges (kk_random_*_rangeObject/*Range) pending KSP-457's own
        // range-random Kotlin migration, registered as members so they remain
        // reachable (see HeaderHelpers+SyntheticRandomStubs.swift). Their arity
        // (1) happens to collide with the bundled scalar overloads of the same
        // name (nextInt(until: Int) etc., Random.kt/URandom.kt) since this key
        // only tracks arity, not parameter types — this is an intentional,
        // by-design overload pair, not an accidental duplicate.
        switch interner.resolve(key.name) {
        case "nextInt", "nextLong", "nextUInt", "nextULong":
            return key.arity == 1
        default:
            return false
        }
    }

    private static func isRuntimeBackedAtomicSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        ownerFQName: [String],
        interner: StringInterner
    ) -> Bool {
        // AtomicMigration.kt carries compatibility aliases as bundled Kotlin
        // extension functions in kotlin.concurrent, but current member-call
        // resolution still needs the receiver-owned synthetic bridge when users
        // import kotlin.concurrent.atomics.AtomicInt/AtomicLong/AtomicReference
        // directly. Retain these runtime-backed aliases until the bundled source
        // path is visible to ordinary member-call lookup.
        switch ownerFQName {
        case ["kotlin", "concurrent", "atomics", "AtomicInt"],
             ["kotlin", "concurrent", "AtomicInt"],
             ["kotlin", "concurrent", "atomics", "AtomicLong"],
             ["kotlin", "concurrent", "AtomicLong"]:
            switch interner.resolve(key.name) {
            case "get", "incrementAndGet", "decrementAndGet":
                return key.arity == 0
            case "set", "getAndSet", "addAndGet":
                return key.arity == 1
            default:
                return false
            }
        case ["kotlin", "concurrent", "atomics", "AtomicReference"],
             ["kotlin", "concurrent", "AtomicReference"]:
            switch interner.resolve(key.name) {
            case "get":
                return key.arity == 0
            case "set", "getAndSet":
                return key.arity == 1
            default:
                return false
            }
        default:
            return false
        }
    }

    private static func isRuntimeBackedListSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        // These List HOF/search/sort sources are bundled as migration targets, but
        // call sites still route through kk_list_* ABI stubs until RF-STDLIB wiring
        // removes the compatibility bridge.
        switch interner.resolve(key.name) {
        case "map", "mapIndexed", "mapNotNull", "flatMap":
            return key.arity == 1
        case "flatten":
            return key.arity == 0
        case "first", "firstOrNull", "last", "lastOrNull", "single", "singleOrNull":
            return key.arity == 0 || key.arity == 1
        case "find", "findLast", "indexOf", "indexOfFirst", "indexOfLast":
            return key.arity == 1
        case "reversed", "sorted":
            return key.arity == 0
        case "shuffled":
            return key.arity == 0 || key.arity == 1
        case "sortedBy", "sortedByDescending", "sortedWith":
            return key.arity == 1
        default:
            return false
        }
    }

    private static func isRuntimeBackedIterableSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        // List.filter is bundled as Kotlin source, but that implementation is
        // only valid for concrete List receivers. Keep the runtime bridge for
        // nominal Iterable<T> receivers, whose values may not expose List indexing.
        interner.resolve(key.name) == "filter" && key.arity == 1
    }

    private static func isRuntimeBackedSequenceSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        // Sequence aggregate HOFs are bundled as migration targets, but call sites
        // still route through kk_sequence_* ABI stubs until RF-STDLIB wiring
        // removes the compatibility bridge.
        switch interner.resolve(key.name) {
        case "map", "mapIndexed", "mapNotNull", "mapIndexedNotNull",
             "filter", "filterNot", "filterIndexed",
             "flatMap", "flatMapIndexed",
             "onEach", "onEachIndexed":
            return key.arity == 1
        case "fold", "scan":
            return key.arity == 2
        case "reduce", "sumOf", "maxByOrNull", "minByOrNull":
            return key.arity == 1
        case "filterNotNull", "filterIsInstance", "requireNoNulls", "withIndex":
            return key.arity == 0
        case "toList", "toSet", "toMutableList":
            // MIGRATION-SEQ-003 bundled these collection-conversion terminals in
            // Kotlin source, but CollectionLiteralLoweringPass call-rewrite still
            // dispatches Sequence.toList/toSet/toMutableList to the kk_sequence_*
            // ABI stubs (see CollectionLiteralLoweringPass+CallRewriteSequenceTerminals
            // and CallLowerer+ReceiverTypePredicates.toMutableListRuntimeCalleeFor...).
            // Retain the synthetic stub's externalLinkName so Sema-level symbol
            // lookups stay consistent with that lowering path.
            return key.arity == 0
        default:
            return false
        }
    }

    private static func buildKeys(
        ast: ASTModule,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> Set<BundledMemberKey> {
        let bundledFileIDs = bundledFileIDs(in: sourceManager)
        guard !bundledFileIDs.isEmpty else {
            return []
        }
        let bundledFiles = ast.sortedFiles.filter {
            bundledFileIDs.contains($0.fileID)
        }
        let topLevelNominalNamesByPackage = collectTopLevelNominalNamesByPackage(
            files: bundledFiles,
            ast: ast
        )
        let builtinNames = BuiltinTypeNames(interner: interner)

        var keys: Set<BundledMemberKey> = []
        for file in bundledFiles {
            let topLevelNominalNames = topLevelNominalNamesByPackage[file.packageFQName] ?? []
            for declID in file.topLevelDecls {
                collectBundledTopLevelDecl(
                    declID: declID,
                    packageFQName: file.packageFQName,
                    topLevelNominalNames: topLevelNominalNames,
                    ast: ast,
                    builtinNames: builtinNames,
                    interner: interner,
                    keys: &keys
                )
            }
        }
        return keys
    }

    private static func buildFromSymbols(
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        interner: StringInterner?
    ) -> BundledDeclarationIndex {
        let bundledFileIDs = bundledFileIDs(in: sourceManager)
        guard !bundledFileIDs.isEmpty else {
            return .empty
        }

        var keys: Set<BundledMemberKey> = []
        for symbol in symbols.allSymbols() {
            guard !symbol.flags.contains(.synthetic) else { continue }
            let fileID = symbols.sourceFileID(for: symbol.id) ?? symbol.declSite?.start.file
            guard let fileID,
                  bundledFileIDs.contains(fileID)
            else {
                continue
            }
            guard let key = makeMemberKey(
                for: symbol,
                symbolID: symbol.id,
                symbols: symbols,
                types: types,
                interner: interner
            )
            else {
                continue
            }
            keys.insert(key)
        }

        return BundledDeclarationIndex(keys: keys)
    }

    private static func makeMemberKey(
        for symbol: SemanticSymbol,
        symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner?
    ) -> BundledMemberKey? {
        let arity: Int
        let receiverType: TypeID?
        switch symbol.kind {
        case .function:
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return nil
            }
            arity = signature.parameterTypes.count
            receiverType = signature.receiverType
        case .property, .field:
            arity = 0
            receiverType = symbols.extensionPropertyReceiverType(for: symbolID)
        default:
            return nil
        }

        let declaredOwnerFQName = ownerFQName(for: symbol, symbolID: symbolID, symbols: symbols)
        let owner = ownerFQName(
            declaredOwnerFQName: declaredOwnerFQName,
            receiverType: receiverType,
            symbols: symbols,
            types: types,
            interner: interner
        ) ?? declaredOwnerFQName
        return BundledMemberKey(ownerFQName: owner, name: symbol.name, arity: arity)
    }

    private static func ownerFQName(
        declaredOwnerFQName: [InternedString],
        receiverType: TypeID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner?
    ) -> [InternedString]? {
        if let receiverType,
           let receiverOwner = receiverOwnerFQName(
               for: receiverType,
               symbols: symbols,
               types: types,
               interner: interner
           )
        {
            return receiverOwner
        }
        return declaredOwnerFQName
    }

    static func receiverOwnerFQName(
        for receiverType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [InternedString]? {
        receiverOwnerFQName(
            for: receiverType,
            symbols: symbols,
            types: types,
            interner: Optional(interner)
        )
    }

    private static func receiverOwnerFQName(
        for receiverType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner?
    ) -> [InternedString]? {
        let nonNullType = types.makeNonNullable(receiverType)
        switch types.kind(of: nonNullType) {
        case let .classType(classType):
            return symbols.symbol(classType.classSymbol)?.fqName
        case let .primitive(primitive, _):
            guard let interner else {
                return nil
            }
            return [interner.intern("kotlin"), interner.intern(primitive.kotlinName)]
        case let .intersection(parts):
            for part in parts {
                if let owner = receiverOwnerFQName(
                    for: part,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) {
                    return owner
                }
            }
            return nil
        default:
            return nil
        }
    }

    private static func ownerFQName(
        for symbol: SemanticSymbol,
        symbolID: SymbolID,
        symbols: SymbolTable
    ) -> [InternedString] {
        if let parent = symbols.parentSymbol(for: symbolID),
           let parentSymbol = symbols.symbol(parent)
        {
            return parentSymbol.fqName
        }
        return Array(symbol.fqName.dropLast())
    }

    private static func bundledFileIDs(in sourceManager: SourceManager) -> Set<FileID> {
        Set(sourceManager.fileIDs().filter { sourceManager.path(of: $0).hasPrefix("__bundled_") })
    }

    private static func addListIterableAliases(to keys: inout Set<BundledMemberKey>, interner: StringInterner) {
        let kotlin = interner.intern("kotlin")
        let collections = interner.intern("collections")
        let listOwnerFQName = [kotlin, collections, interner.intern("List")]
        let iterableOwnerFQName = [kotlin, collections, interner.intern("Iterable")]

        let listKeys = keys.filter { $0.ownerFQName == listOwnerFQName }
        for key in listKeys {
            keys.insert(
                BundledMemberKey(
                    ownerFQName: iterableOwnerFQName,
                    name: key.name,
                    arity: key.arity
                )
            )
        }
    }

    private static func collectBundledTopLevelDecl(
        declID: DeclID,
        packageFQName: [InternedString],
        topLevelNominalNames: Set<InternedString>,
        ast: ASTModule,
        builtinNames: BuiltinTypeNames,
        interner: StringInterner,
        keys: inout Set<BundledMemberKey>
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }

        switch decl {
        case let .funDecl(funDecl):
            guard let receiverTypeID = funDecl.receiverType,
                  let receiverType = ast.arena.typeRef(receiverTypeID),
                  let ownerFQName = fqName(
                    for: receiverType,
                    relativeTo: packageFQName,
                    topLevelNominalNames: topLevelNominalNames,
                    ast: ast,
                    builtinNames: builtinNames,
                    interner: interner
                  )
            else {
                return
            }
            keys.insert(
                BundledMemberKey(
                    ownerFQName: ownerFQName,
                    name: funDecl.name,
                    arity: funDecl.valueParams.count
                )
            )

        case let .propertyDecl(propertyDecl):
            guard let receiverTypeID = propertyDecl.receiverType,
                  let receiverType = ast.arena.typeRef(receiverTypeID),
                  let ownerFQName = fqName(
                    for: receiverType,
                    relativeTo: packageFQName,
                    topLevelNominalNames: topLevelNominalNames,
                    ast: ast,
                    builtinNames: builtinNames,
                    interner: interner
                  )
            else {
                return
            }
            keys.insert(
                BundledMemberKey(
                    ownerFQName: ownerFQName,
                    name: propertyDecl.name,
                    arity: 0
                )
            )

        case let .classDecl(classDecl):
            let ownerFQName = packageFQName + [classDecl.name]
            collectBundledNominalMembers(
                memberFunctions: classDecl.memberFunctions,
                memberProperties: classDecl.memberProperties,
                nestedClasses: classDecl.nestedClasses,
                nestedObjects: classDecl.nestedObjects,
                companionObject: classDecl.companionObject,
                ownerFQName: ownerFQName,
                ast: ast,
                keys: &keys
            )

        case let .interfaceDecl(interfaceDecl):
            let ownerFQName = packageFQName + [interfaceDecl.name]
            collectBundledNominalMembers(
                memberFunctions: interfaceDecl.memberFunctions,
                memberProperties: interfaceDecl.memberProperties,
                nestedClasses: interfaceDecl.nestedClasses,
                nestedObjects: interfaceDecl.nestedObjects,
                companionObject: interfaceDecl.companionObject,
                ownerFQName: ownerFQName,
                ast: ast,
                keys: &keys
            )

        case let .objectDecl(objectDecl):
            let ownerFQName = packageFQName + [objectDecl.name]
            collectBundledNominalMembers(
                memberFunctions: objectDecl.memberFunctions,
                memberProperties: objectDecl.memberProperties,
                nestedClasses: objectDecl.nestedClasses,
                nestedObjects: objectDecl.nestedObjects,
                companionObject: nil,
                ownerFQName: ownerFQName,
                ast: ast,
                keys: &keys
            )

        default:
            break
        }
    }

    private static func collectBundledNominalMembers(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        companionObject: DeclID?,
        ownerFQName: [InternedString],
        ast: ASTModule,
        keys: inout Set<BundledMemberKey>
    ) {
        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(funDecl) = decl
            else {
                continue
            }
            keys.insert(
                BundledMemberKey(
                    ownerFQName: ownerFQName,
                    name: funDecl.name,
                    arity: funDecl.valueParams.count
                )
            )
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            keys.insert(
                BundledMemberKey(
                    ownerFQName: ownerFQName,
                    name: propertyDecl.name,
                    arity: 0
                )
            )
        }

        for declID in nestedClasses + nestedObjects {
            collectBundledNestedDecl(
                declID: declID,
                ownerFQName: ownerFQName,
                ast: ast,
                keys: &keys
            )
        }

        if let companionObject {
            collectBundledNestedDecl(
                declID: companionObject,
                ownerFQName: ownerFQName,
                ast: ast,
                keys: &keys
            )
        }
    }

    private static func collectBundledNestedDecl(
        declID: DeclID,
        ownerFQName: [InternedString],
        ast: ASTModule,
        keys: inout Set<BundledMemberKey>
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }

        switch decl {
        case let .classDecl(classDecl):
            collectBundledNominalMembers(
                memberFunctions: classDecl.memberFunctions,
                memberProperties: classDecl.memberProperties,
                nestedClasses: classDecl.nestedClasses,
                nestedObjects: classDecl.nestedObjects,
                companionObject: classDecl.companionObject,
                ownerFQName: ownerFQName + [classDecl.name],
                ast: ast,
                keys: &keys
            )
        case let .interfaceDecl(interfaceDecl):
            collectBundledNominalMembers(
                memberFunctions: interfaceDecl.memberFunctions,
                memberProperties: interfaceDecl.memberProperties,
                nestedClasses: interfaceDecl.nestedClasses,
                nestedObjects: interfaceDecl.nestedObjects,
                companionObject: interfaceDecl.companionObject,
                ownerFQName: ownerFQName + [interfaceDecl.name],
                ast: ast,
                keys: &keys
            )
        case let .objectDecl(objectDecl):
            collectBundledNominalMembers(
                memberFunctions: objectDecl.memberFunctions,
                memberProperties: objectDecl.memberProperties,
                nestedClasses: objectDecl.nestedClasses,
                nestedObjects: objectDecl.nestedObjects,
                companionObject: nil,
                ownerFQName: ownerFQName + [objectDecl.name],
                ast: ast,
                keys: &keys
            )
        default:
            break
        }
    }

    private static func fqName(
        for typeRef: TypeRef,
        relativeTo packageFQName: [InternedString],
        topLevelNominalNames: Set<InternedString>,
        ast: ASTModule,
        builtinNames: BuiltinTypeNames,
        interner: StringInterner
    ) -> [InternedString]? {
        switch typeRef {
        case let .named(path, _, _):
            guard let first = path.first else {
                return nil
            }
            if pathStarts(with: path, prefix: packageFQName) {
                return path
            }
            // Single-segment names normally resolve relative to the current
            // bundled package (e.g. `Duration.foo()` inside kotlin.time), but
            // built-in root types (Int, String, ...) live under `kotlin`
            // regardless of which subpackage references them. Without this
            // check, e.g. `Int.seconds` declared in kotlin.time was keyed as
            // kotlin.time.Int instead of kotlin.Int, so the KSP-002 skip guard
            // never matched and a conflicting synthetic stub was registered
            // alongside the bundled source declaration.
            if path.count == 1, isBuiltinRootTypeName(first, builtinNames: builtinNames) {
                return [interner.intern("kotlin"), first]
            }
            if path.count == 1 || topLevelNominalNames.contains(first) {
                return packageFQName + path
            }
            return path
        case let .annotated(base, _):
            guard let baseRef = ast.arena.typeRef(base) else {
                return nil
            }
            return fqName(
                for: baseRef,
                relativeTo: packageFQName,
                topLevelNominalNames: topLevelNominalNames,
                ast: ast,
                builtinNames: builtinNames,
                interner: interner
            )
        case .functionType, .intersection:
            return nil
        }
    }

    /// True when `name` is one of the primitive types that live directly
    /// under the `kotlin` package (Int, Long, Double, ...), matching the
    /// `.primitive` case that `receiverOwnerFQName(for:symbols:types:interner:)`
    /// resolves once a `TypeID` is available. Keeping the two in sync is what
    /// makes the `shouldSkipRegistration` key lookup find bundled source
    /// declarations.
    ///
    /// Deliberately narrower than `BuiltinTypeNames`: String/Any/Unit/Nothing
    /// are NOT included here because `receiverOwnerFQName` only handles
    /// `.classType` and `.primitive` type kinds, not `.stringStruct`, `.any`,
    /// `.unit`, or `.nothing` — including them here without a matching case
    /// there would make this function key bundled declarations under
    /// `["kotlin", "String"]` etc. while the skip-guard check still falls
    /// back to the declared (non-root) owner, so the two would never match.
    private static func isBuiltinRootTypeName(_ name: InternedString, builtinNames: BuiltinTypeNames) -> Bool {
        builtinNames.primitiveType(for: name) != nil
    }

    private static func collectTopLevelNominalNamesByPackage(
        files: [ASTFile],
        ast: ASTModule
    ) -> [[InternedString]: Set<InternedString>] {
        var namesByPackage: [[InternedString]: Set<InternedString>] = [:]
        for file in files {
            for declID in file.topLevelDecls {
                guard let name = topLevelNominalName(declID: declID, ast: ast) else {
                    continue
                }
                namesByPackage[file.packageFQName, default: Set<InternedString>()].insert(name)
            }
        }
        return namesByPackage
    }

    private static func topLevelNominalName(declID: DeclID, ast: ASTModule) -> InternedString? {
        guard let decl = ast.arena.decl(declID) else {
            return nil
        }
        switch decl {
        case let .classDecl(classDecl):
            return classDecl.name
        case let .interfaceDecl(interfaceDecl):
            return interfaceDecl.name
        case let .objectDecl(objectDecl):
            return objectDecl.name
        default:
            return nil
        }
    }

    private static func pathStarts(with path: [InternedString], prefix: [InternedString]) -> Bool {
        guard path.count >= prefix.count else {
            return false
        }
        for (index, element) in prefix.enumerated() where path[index] != element {
            return false
        }
        return true
    }
}

/// Active bundled-index context while `registerSyntheticDelegateStubs` runs.
enum BundledSyntheticStubRegistration {
    private static let bundledIndexKey = "KSwiftK.BundledSyntheticStubRegistration.bundledIndex"
    private static let typesKey = "KSwiftK.BundledSyntheticStubRegistration.types"
    private static let skippedCountKey = "KSwiftK.BundledSyntheticStubRegistration.skippedCount"
    private static let preBundledPassKey = "KSwiftK.BundledSyntheticStubRegistration.preBundledPass"
    private static let postBundledPassKey = "KSwiftK.BundledSyntheticStubRegistration.postBundledPass"

    private static var storage: NSMutableDictionary {
        Thread.current.threadDictionary
    }

    static var bundledIndex: BundledDeclarationIndex {
        get { storage[bundledIndexKey] as? BundledDeclarationIndex ?? .empty }
        set { storage[bundledIndexKey] = newValue }
    }

    static var types: TypeSystem? {
        get { storage[typesKey] as? TypeSystem }
        set {
            if let newValue {
                storage[typesKey] = newValue
            } else {
                storage.removeObject(forKey: typesKey)
            }
        }
    }

    static var skippedCount: Int {
        get { storage[skippedCountKey] as? Int ?? 0 }
        set { storage[skippedCountKey] = newValue }
    }

    /// When true, extension-member stub registration is deferred to the post-bundled pass.
    static var preBundledPass: Bool {
        get { storage[preBundledPassKey] as? Bool ?? false }
        set { storage[preBundledPassKey] = newValue }
    }

    /// When true, only extension-member stubs are registered (post-bundled pass).
    static var postBundledPass: Bool {
        get { storage[postBundledPassKey] as? Bool ?? false }
        set { storage[postBundledPassKey] = newValue }
    }

    static func clear() {
        storage.removeObject(forKey: bundledIndexKey)
        storage.removeObject(forKey: typesKey)
        storage.removeObject(forKey: skippedCountKey)
        storage.removeObject(forKey: preBundledPassKey)
        storage.removeObject(forKey: postBundledPassKey)
    }

    static func shouldSkipRegistration(
        declaredOwnerFQName: [InternedString],
        receiverType: TypeID?,
        name: InternedString,
        arity: Int,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        if postBundledPass, receiverType == nil {
            skippedCount += 1
            return true
        }
        if preBundledPass, receiverType != nil {
            skippedCount += 1
            return true
        }
        let ownerFQName = BundledDeclarationIndex.ownerFQName(
            declaredOwnerFQName: declaredOwnerFQName,
            receiverType: receiverType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let key = BundledMemberKey(ownerFQName: ownerFQName, name: name, arity: arity)
        if BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner) {
            return false
        }
        guard bundledIndex.contains(key) else {
            return false
        }
        skippedCount += 1
        return true
    }
}
