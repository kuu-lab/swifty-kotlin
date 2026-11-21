import Foundation

struct BundledMemberKey: Hashable, Sendable {
    let ownerFQName: [InternedString]
    let name: InternedString
    let arity: Int
}

package struct BundledDeclarationIndex: Sendable {
    static let empty = BundledDeclarationIndex(keys: [], nominalFQNames: [])

    private let keys: Set<BundledMemberKey>
    private let nominalFQNames: Set<[InternedString]>
    private let importedMemberIndex: PrecomputedBundledMemberIndex?

    init(
        keys: Set<BundledMemberKey> = [],
        nominalFQNames: Set<[InternedString]> = [],
        importedMemberIndex: PrecomputedBundledMemberIndex? = nil
    ) {
        self.keys = keys
        self.nominalFQNames = nominalFQNames
        self.importedMemberIndex = importedMemberIndex
    }

    func contains(_ key: BundledMemberKey) -> Bool {
        keys.contains(key)
            || importedMemberIndex?.contains(owner: key.ownerFQName, name: key.name, arity: key.arity) == true
    }

    func contains(owner: [InternedString], name: InternedString, arity: Int) -> Bool {
        contains(BundledMemberKey(ownerFQName: owner, name: name, arity: arity))
    }

    func contains(ownerFQName: [InternedString], name: InternedString, arity: Int) -> Bool {
        contains(owner: ownerFQName, name: name, arity: arity)
    }

    func contains(ownerFQName: [InternedString], name: InternedString) -> Bool {
        keys.contains { $0.ownerFQName == ownerFQName && $0.name == name }
            || importedMemberIndex?.contains(owner: ownerFQName, name: name) == true
    }

    func containsNominal(fqName: [InternedString]) -> Bool {
        nominalFQNames.contains(fqName)
    }

    mutating func insert(_ key: BundledMemberKey) {
        self = BundledDeclarationIndex(
            keys: keys.union([key]),
            nominalFQNames: nominalFQNames,
            importedMemberIndex: importedMemberIndex
        )
    }

    mutating func insertImportedStdlibSymbols(
        keys: Set<BundledMemberKey>,
        interner: StringInterner,
        precomputedMemberIndex: PrecomputedBundledMemberIndex? = nil
    ) {
        var merged = self.keys.union(keys)
        Self.addListIterableAliases(to: &merged, interner: interner)
        self = BundledDeclarationIndex(
            keys: merged,
            nominalFQNames: nominalFQNames,
            importedMemberIndex: precomputedMemberIndex ?? importedMemberIndex
        )
    }

    package static func precomputedMemberIndexData(
        records: [MetadataRecord],
        interner: StringInterner
    ) -> Data {
        var keys: Set<BundledMemberKey> = []
        for record in records {
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
            let nameString = record.fqName.lastIndex(of: ".")
                .map { String(record.fqName[record.fqName.index(after: $0)...]) }
                ?? record.fqName
            let owner = ownerString.isEmpty
                ? []
                : ownerString.split(separator: ".").map { interner.intern(String($0)) }
            keys.insert(BundledMemberKey(
                ownerFQName: owner,
                name: interner.intern(nameString),
                arity: arity
            ))
        }
        addListIterableAliases(to: &keys, interner: interner)
        return PrecomputedBundledMemberIndex.encode(keys: keys, interner: interner)
    }

    static func build(ast: ASTModule, sourceManager: SourceManager, interner: StringInterner) -> BundledDeclarationIndex {
        var keys = buildKeys(ast: ast, sourceManager: sourceManager, interner: interner)
        addListIterableAliases(to: &keys, interner: interner)
        return BundledDeclarationIndex(
            keys: keys,
            nominalFQNames: buildNominalFQNames(ast: ast, sourceManager: sourceManager)
        )
    }

    static func build(
        ast: ASTModule,
        symbols _: SymbolTable,
        types _: TypeSystem,
        sourceManager: SourceManager,
        interner: StringInterner,
        includeUserSources: Bool = false
    ) -> BundledDeclarationIndex {
        let extraFiles = includeUserSources ? Set(sourceManager.fileIDs().filter { sourceManager.origin(of: $0) == .user }) : []
        var keys = buildKeys(ast: ast, sourceManager: sourceManager, interner: interner, extraFiles: extraFiles)
        addListIterableAliases(to: &keys, interner: interner)
        return BundledDeclarationIndex(
            keys: keys,
            nominalFQNames: buildNominalFQNames(ast: ast, sourceManager: sourceManager, extraFiles: extraFiles)
        )
    }

    static func build(sourceManager: SourceManager, symbols: SymbolTable, types: TypeSystem) -> BundledDeclarationIndex {
        buildFromSymbols(
            symbols: symbols,
            types: types,
            sourceManager: sourceManager,
            interner: nil
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
            guard !symbol.flags.contains(.importedLibrary) else { continue }
            guard symbol.kind == .function || symbol.kind == .property else { continue }
            guard !Self.isSyntheticAnnotationClassObjectMethod(symbol, symbols: symbols, interner: interner) else {
                continue
            }
            guard !Self.isSyntheticPropertyAccessor(symbol, symbols: symbols) else {
                continue
            }
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
            guard !Self.isSyntheticAliasForSourceBackedMember(symbol, symbols: symbols) else {
                continue
            }
            guard !Self.isSyntheticAliasForSourceBackedProperty(
                symbol,
                key: key,
                symbols: symbols,
                types: types,
                interner: interner
            ) else {
                continue
            }
            if Self.isSyntheticPairCopyOverlapWithSourceBackedExtension(
                symbol,
                key: key,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                continue
            }
            if Self.isSyntheticOverlapWithSourceBackedMutableCollectionExtension(
                symbol,
                key: key,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                continue
            }
            if Self.isSyntheticJoinToTransformOverload(symbol.id, key: key, symbols: symbols, types: types, interner: interner) {
                continue
            }
            if Self.hasSourceBackedFunctionOverlap(symbol, key: key, symbols: symbols, types: types, interner: interner) {
                continue
            }
            if Self.isSyntheticOpenEndRangeGenericContainsRetainedOverlap(
                symbol,
                key: key,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                continue
            }
            if Self.isSyntheticCInteropPointerOperatorOverlap(
                symbol,
                key: key,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                continue
            }
            guard contains(key) else { continue }
            if Self.isSyntheticMutableListCollectionOverload(
                symbol.id,
                key: key,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                continue
            }
            guard reported.insert(key).inserted else { continue }

            let ownerDisplay = key.ownerFQName.map { interner.resolve($0) }.joined(separator: ".")
            let memberDisplay = interner.resolve(key.name)
            diagnostics.warning(
                "KSWIFTK-SEMA-0102",
                "Synthetic stub '\(memberDisplay)' on '\(ownerDisplay)' (arity \(key.arity)) duplicates bundled stdlib declaration; KSP-002 skip guard missed.",
                range: nil
            )
        }
    }

    private static func isSyntheticAnnotationClassObjectMethod(
        _ symbol: SemanticSymbol,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        guard symbol.kind == .function,
              symbol.flags.contains(.overrideMember),
              let ownerID = symbols.parentSymbol(for: symbol.id),
              symbols.symbol(ownerID)?.kind == .annotationClass,
              let signature = symbols.functionSignature(for: symbol.id)
        else {
            return false
        }

        switch interner.resolve(symbol.name) {
        case "equals":
            return signature.parameterTypes.count == 1
        case "hashCode", "toString":
            return signature.parameterTypes.isEmpty
        default:
            return false
        }
    }

    private static func isSyntheticPairCopyOverlapWithSourceBackedExtension(
        _ symbol: SemanticSymbol,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        let pairFQName = ["kotlin", "Pair"].map { interner.intern($0) }
        let copyName = interner.intern("copy")
        guard symbol.kind == .function,
              key.ownerFQName == pairFQName,
              key.name == copyName,
              let pairSymbolID = symbols.parentSymbol(for: symbol.id),
              symbols.symbol(pairSymbolID)?.fqName == pairFQName
        else {
            return false
        }

        let kotlinCopyFQName = ["kotlin", "copy"].map { interner.intern($0) }
        return symbols.lookupByShortName(copyName).contains { candidateID in
            guard let candidate = symbols.symbol(candidateID),
                  candidate.kind == .function,
                  candidate.fqName == kotlinCopyFQName,
                  symbols.isSourceBackedSymbol(candidate.id),
                  let signature = symbols.functionSignature(for: candidate.id),
                  signature.receiverType != nil,
                  let candidateKey = memberKey(
                      for: candidate,
                      symbolID: candidate.id,
                      symbols: symbols,
                      types: types,
                      interner: interner
                  )
            else {
                return false
            }
            return candidateKey == key
        }
    }

    private static func isSyntheticPropertyAccessor(
        _ symbol: SemanticSymbol,
        symbols: SymbolTable
    ) -> Bool {
        guard symbol.kind == .function,
              let propertySymbol = symbols.parentSymbol(for: symbol.id),
              symbols.symbol(propertySymbol)?.kind == .property
        else {
            return false
        }

        return symbols.extensionPropertyGetterAccessor(for: propertySymbol) == symbol.id
            || symbols.extensionPropertySetterAccessor(for: propertySymbol) == symbol.id
            || symbols.accessorOwnerProperty(for: symbol.id) == propertySymbol
    }

    private static func isSyntheticOverlapWithSourceBackedMutableCollectionExtension(
        _ symbol: SemanticSymbol,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        let kotlinCollections = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        let mutableCollection = kotlinCollections + [interner.intern("MutableCollection")]
        guard key.ownerFQName == mutableCollection,
              ["addAll", "remove", "removeAll", "retainAll"].contains(interner.resolve(symbol.name))
        else {
            return false
        }

        let sourceFunctionFQName = kotlinCollections + [symbol.name]
        return symbols.lookupAll(fqName: sourceFunctionFQName).contains { candidateID in
            guard let candidate = symbols.symbol(candidateID),
                  candidate.kind == .function,
                  (!candidate.flags.contains(.synthetic) || candidate.flags.contains(.importedLibrary)),
                  candidate.name == symbol.name,
                  candidate.fqName == sourceFunctionFQName,
                  let signature = symbols.functionSignature(for: candidate.id),
                  let receiverType = signature.receiverType,
                  let receiverOwner = receiverOwnerFQName(
                      for: receiverType,
                      symbols: symbols,
                      types: types,
                      interner: interner
                  )
            else {
                return false
            }
            return receiverOwner == mutableCollection
        }
    }

    private static func isSyntheticCInteropPointerOperatorOverlap(
        _ symbol: SemanticSymbol,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        let cinteropPackage = [interner.intern("kotlinx"), interner.intern("cinterop")]
        let cPointerFQName = cinteropPackage + [interner.intern("CPointer")]
        guard key.ownerFQName == cPointerFQName,
              ["plus", "get", "set"].contains(interner.resolve(key.name)),
              let signature = symbols.functionSignature(for: symbol.id),
              let receiverType = signature.receiverType,
              receiverOwnerFQName(
                  for: receiverType,
                  symbols: symbols,
                  types: types,
                  interner: interner
              ) == cPointerFQName
        else {
            return false
        }

        let sourceFunctionFQName = cinteropPackage + [key.name]
        return symbols.lookupAll(fqName: sourceFunctionFQName).contains { candidateID in
            guard let candidate = symbols.symbol(candidateID),
                  candidate.kind == .function,
                  !candidate.flags.contains(.synthetic),
                  candidate.fqName == sourceFunctionFQName,
                  let candidateSignature = symbols.functionSignature(for: candidateID),
                  let candidateReceiver = candidateSignature.receiverType,
                  receiverOwnerFQName(
                      for: candidateReceiver,
                      symbols: symbols,
                      types: types,
                      interner: interner
                  ) == cPointerFQName
            else {
                return false
            }
            return true
        }
    }

    private static func isSyntheticAliasForSourceBackedMember(
        _ symbol: SemanticSymbol,
        symbols: SymbolTable
    ) -> Bool {
        guard symbol.kind == .function,
              symbol.declSite == nil,
              let parentSymbol = symbols.parentSymbol(for: symbol.id),
              let signature = symbols.functionSignature(for: symbol.id),
              let externalLinkName = symbols.externalLinkName(for: symbol.id),
              !externalLinkName.isEmpty
        else {
            return false
        }

        return symbols.lookupByShortName(symbol.name).contains { candidateID in
            guard let candidate = symbols.symbol(candidateID),
                  candidate.id != symbol.id,
                  candidate.kind == .function,
                  !candidate.flags.contains(.synthetic),
                  candidate.declSite != nil,
                  candidate.name == symbol.name,
                  candidate.fqName != symbol.fqName,
                  symbols.parentSymbol(for: candidate.id) == parentSymbol,
                  symbols.functionSignature(for: candidate.id) == signature,
                  symbols.externalLinkName(for: candidate.id) == externalLinkName
            else {
                return false
            }
            return true
        }
    }

    private static func isSyntheticAliasForSourceBackedProperty(
        _ symbol: SemanticSymbol,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        guard symbol.kind == .property,
              symbol.flags.contains(.synthetic)
        else {
            return false
        }
        return symbols.lookupByShortName(symbol.name).contains { candidateID in
            guard let candidate = symbols.symbol(candidateID),
                  candidate.id != symbol.id,
                  candidate.kind == .property,
                  symbols.isSourceBackedSymbol(candidate.id),
                  candidate.name == symbol.name,
                  candidate.fqName != symbol.fqName,
                  let candidateKey = memberKey(
                      for: candidate,
                      symbolID: candidate.id,
                      symbols: symbols,
                      types: types,
                      interner: interner
                  )
            else {
                return false
            }
            return candidateKey == key
        }
    }

    private static func isSyntheticJoinToTransformOverload(
        _ symbolID: SymbolID,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        let name = interner.resolve(key.name)
        guard name == "joinTo" || name == "joinToString" else {
            return false
        }
        guard let signature = symbols.functionSignature(for: symbolID) else {
            return false
        }
        return signature.parameterTypes.contains { paramType in
            if case .functionType = types.kind(of: types.makeNonNullable(paramType)) {
                return true
            }
            return false
        }
    }

    private static func isSyntheticMutableListCollectionOverload(
        _ symbolID: SymbolID,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        let mutableListFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ]
        guard key.ownerFQName == mutableListFQName,
              key.arity == 1,
              interner.resolve(key.name) == "removeAll" || interner.resolve(key.name) == "retainAll",
              let signature = symbols.functionSignature(for: symbolID),
              let parameterType = signature.parameterTypes.first,
              case let .classType(parameterClass) = types.kind(of: types.makeNonNullable(parameterType)),
              let parameterSymbol = symbols.symbol(parameterClass.classSymbol)
        else {
            return false
        }
        let collectionFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Collection"),
        ]
        return parameterSymbol.fqName == collectionFQName
    }

    private static func hasSourceBackedFunctionOverlap(
        _ symbol: SemanticSymbol,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        let progressionFQNames = [
            "IntProgression", "LongProgression", "CharProgression",
            "UIntProgression", "ULongProgression",
        ].map { ["kotlin", "ranges", $0].map { interner.intern($0) } }
        let migratedNames = Set(["first", "firstOrNull", "last", "lastOrNull"].map { interner.intern($0) })
        guard symbol.kind == .property,
              progressionFQNames.contains(key.ownerFQName),
              migratedNames.contains(key.name)
        else {
            return false
        }
        return symbols.lookupByShortName(key.name).contains { candidateID in
            guard let candidate = symbols.symbol(candidateID),
                  candidate.kind == .function,
                  symbols.isSourceBackedSymbol(candidate.id),
                  let candidateKey = memberKey(
                      for: candidate,
                      symbolID: candidate.id,
                      symbols: symbols,
                      types: types,
                      interner: interner
                  )
            else {
                return false
            }
            return candidateKey == key
        }
    }

    private static func isSyntheticOpenEndRangeGenericContainsRetainedOverlap(
        _ symbol: SemanticSymbol,
        key: BundledMemberKey,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        let openEndRangeFQName = ["kotlin", "ranges", "OpenEndRange"].map { interner.intern($0) }
        guard symbol.kind == .function,
              key.ownerFQName == openEndRangeFQName,
              interner.resolve(key.name) == "contains",
              key.arity == 1,
              let signature = symbols.functionSignature(for: symbol.id),
              signature.classTypeParameterCount == 1,
              let receiverType = signature.receiverType,
              receiverOwnerFQName(
                  for: receiverType,
                  symbols: symbols,
                  types: types,
                  interner: interner
              ) == openEndRangeFQName
        else {
            return false
        }

        return symbols.lookupByShortName(key.name).contains { candidateID in
            guard let candidate = symbols.symbol(candidateID),
                  candidate.kind == .function,
                  symbols.isSourceBackedSymbol(candidate.id),
                  candidate.name == key.name,
                  let candidateKey = memberKey(
                      for: candidate,
                      symbolID: candidate.id,
                      symbols: symbols,
                      types: types,
                      interner: interner
                  )
            else {
                return false
            }
            return candidateKey.ownerFQName == openEndRangeFQName
                && candidateKey.arity == key.arity
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
            return isRuntimeBackedSequenceSyntheticRetainedOverlap()
        }
        if ownerFQName == ["kotlin", "collections", "MutableSet"] {
            return interner.resolve(key.name) == "addAll" && key.arity == 1
        }
        if ownerFQName == ["kotlin", "comparisons"] {
            return isRuntimeBackedComparisonsSyntheticRetainedOverlap(key, interner: interner)
        }
        if ownerFQName == ["kotlin", "collections", "Map"] {
            return interner.resolve(key.name) == "get" && key.arity == 1
        }
        if ownerFQName == ["kotlinx", "cinterop", "CPointer"] {
            return interner.resolve(key.name) == "get" && key.arity == 1
        }
        return false
    }

    private static func isRuntimeBackedListSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        switch interner.resolve(key.name) {
        default:
            return false
        }
    }

    private static func isRuntimeBackedIterableSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        switch interner.resolve(key.name) {
        case "filter",
             "reduce", "reduceIndexed":
            return key.arity == 1
        default:
            return false
        }
    }

    private static func isRuntimeBackedSequenceSyntheticRetainedOverlap() -> Bool {
        return false
    }

    private static func isRuntimeBackedComparisonsSyntheticRetainedOverlap(
        _ key: BundledMemberKey,
        interner: StringInterner
    ) -> Bool {
        switch interner.resolve(key.name) {
        case "compareBy":
            return key.arity == 1 || key.arity == 2 || key.arity == 3
        default:
            return false
        }
    }

    private static func buildKeys(
        ast: ASTModule,
        sourceManager: SourceManager,
        interner: StringInterner,
        extraFiles: Set<FileID> = []
    ) -> Set<BundledMemberKey> {
        let bundledFileIDs = bundledFileIDs(in: sourceManager).union(extraFiles)
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
        let defaultImportedNameToPackage = defaultImportMap(
            topLevelNominalNamesByPackage: topLevelNominalNamesByPackage,
            interner: interner
        )
        let builtinNames = BuiltinTypeNames(interner: interner)

        var keys: Set<BundledMemberKey> = []
        for file in bundledFiles {
            let topLevelNominalNames = topLevelNominalNamesByPackage[file.packageFQName] ?? []
            var importedNameToPackage = defaultImportedNameToPackage
            for importDecl in file.imports where !importDecl.isWildcard && importDecl.alias == nil {
                if let name = importDecl.path.last {
                    importedNameToPackage[name] = Array(importDecl.path.dropLast())
                }
            }
            for declID in file.topLevelDecls {
                collectBundledTopLevelDecl(
                    declID: declID,
                    packageFQName: file.packageFQName,
                    topLevelNominalNames: topLevelNominalNames,
                    defaultImportedNameToPackage: importedNameToPackage,
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

    private static func buildNominalFQNames(
        ast: ASTModule,
        sourceManager: SourceManager,
        extraFiles: Set<FileID> = []
    ) -> Set<[InternedString]> {
        let bundledFileIDs = bundledFileIDs(in: sourceManager).union(extraFiles)
        guard !bundledFileIDs.isEmpty else {
            return []
        }

        var fqNames: Set<[InternedString]> = []
        for file in ast.sortedFiles where bundledFileIDs.contains(file.fileID) {
            for declID in file.topLevelDecls {
                guard let name = topLevelNominalName(declID: declID, ast: ast) else {
                    continue
                }
                fqNames.insert(file.packageFQName + [name])
            }
        }
        return fqNames
    }

    private static func makeMemberKey(
        for symbol: SemanticSymbol,
        symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner?
    ) -> BundledMemberKey? {
        // Imported index shells carry arity and receiver-owner shape in the
        // compact v2 index. Answering from it keeps arity-key scans (the
        // retained-overlap gates below walk `allSymbols()`) from forcing a
        // declaration-body materialization per candidate.
        if let indexShape = symbols.importedMemberIndexShape(for: symbolID) {
            let owner = indexShape.receiverOwnerFQName ?? Array(symbol.fqName.dropLast())
            return BundledMemberKey(ownerFQName: owner, name: symbol.name, arity: indexShape.arity)
        }
        let arity: Int
        let receiverType: TypeID?
        switch symbol.kind {
        case .function:
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return nil
            }
            arity = signature.parameterTypes.count
            receiverType = signature.receiverType
        case .constructor:
            // Source-backed constructors must keep suppressing their synthetic
            // counterparts when the index is rebuilt from imported stdlib
            // symbols (e.g. `kotlin.concurrent.AtomicReference(value)`), since
            // residual registration runs before the artifact's own keys merge.
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return nil
            }
            arity = signature.parameterTypes.count
            receiverType = nil
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
        case .kClassType:
            // `KClass<T>` receivers (e.g. `T::class` expressions) use the
            // dedicated `.kClassType` representation rather than an ordinary
            // `.classType` wrapping the `KClass` interface symbol. Extensions
            // declared with a `KClass<...>` receiver (bundled stdlib Kotlin
            // source under Sources/CompilerCore/Stdlib/kotlin/reflect/) must
            // resolve to the same owner FQName as the `KClass` interface
            // symbol so member-call candidate lookup (which keys off
            // ownerFQName + memberName) finds them.
            guard let kClassSymbol = types.kClassInterfaceSymbol else {
                return nil
            }
            return symbols.symbol(kClassSymbol)?.fqName
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
        Set(sourceManager.fileIDs().filter { sourceManager.origin(of: $0)?.isBundledStdlib == true })
    }

    private static func addListIterableAliases(to keys: inout Set<BundledMemberKey>, interner: StringInterner) {
        let kotlin = interner.intern("kotlin")
        let collections = interner.intern("collections")
        let listOwnerFQName = [kotlin, collections, interner.intern("List")]
        let iterableOwnerFQName = [kotlin, collections, interner.intern("Iterable")]
        // Aliasing List member implementations to Iterable suppresses synthetic
        // Iterable stubs. List zero-arg accessors (any/none/count/first/last/single/singleOrNull)
        // require a concrete Collection with a size/indices contract; they cannot
        // be served by the List source for an Iterable receiver.
        // `iterator` is likewise non-aliased: Iterable.iterator is itself a
        // declared member (the retained `kk_iterable_iterator` stub carries a
        // lazy, thrown-channel contract — KSP-998) rather than a default impl
        // that List's source declaration can stand in for.
        let nonAliasedZeroArgNames = Set([
            interner.intern("any"),
            interner.intern("none"),
            interner.intern("count"),
            interner.intern("first"),
            interner.intern("iterator"),
            interner.intern("last"),
            interner.intern("single"),
            interner.intern("singleOrNull"),
        ])
        // ListAggregateHOF.kt's fold/reduce/scan family (Sources/CompilerCore/
        // Stdlib/kotlin/collections/ListAggregateHOF.kt) is implemented with
        // `size`/`this[i]` indexed access, which only List supports. Keep these
        // List declarations unaliased so List receivers select the specialized
        // source implementation instead of the generic Iterable declaration.
        // Iterable reduce/reduceIndexed/reduceRight* declarations are now
        // source-backed in Iterables.kt; no synthetic member is needed for the
        // plain Iterable receiver. The remaining names here (foldRight and
        // friends, scan/runningFold/...) use the bundled Sequence source body
        // when the collection-flow fallback explicitly permits an Iterable receiver.
        let nonAliasedIndexedAccessNames = Set([
            interner.intern("fold"),
            interner.intern("foldIndexed"),
            interner.intern("foldRight"),
            interner.intern("foldRightIndexed"),
            interner.intern("reduce"),
            interner.intern("reduceIndexed"),
            interner.intern("reduceOrNull"),
            interner.intern("reduceIndexedOrNull"),
            interner.intern("reduceRight"),
            interner.intern("reduceRightIndexed"),
            interner.intern("reduceRightOrNull"),
            interner.intern("reduceRightIndexedOrNull"),
            interner.intern("scan"),
            interner.intern("scanIndexed"),
            interner.intern("runningFold"),
            interner.intern("runningFoldIndexed"),
            interner.intern("runningReduce"),
            interner.intern("runningReduceIndexed"),
        ])

        let listKeys = keys.filter { $0.ownerFQName == listOwnerFQName }
        for key in listKeys {
            if key.arity == 0, nonAliasedZeroArgNames.contains(key.name) {
                continue
            }
            if nonAliasedIndexedAccessNames.contains(key.name) {
                continue
            }
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
        defaultImportedNameToPackage: [InternedString: [InternedString]],
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
            let ownerFQName: [InternedString]
            if let receiverTypeID = funDecl.receiverType,
               let receiverType = ast.arena.typeRef(receiverTypeID),
               let resolvedOwner = fqName(
                   for: receiverType,
                   relativeTo: packageFQName,
                   topLevelNominalNames: topLevelNominalNames,
                   defaultImportedNameToPackage: defaultImportedNameToPackage,
                   ast: ast,
                   builtinNames: builtinNames,
                   interner: interner
               )
            {
                ownerFQName = resolvedOwner
            } else if funDecl.receiverType == nil {
                ownerFQName = packageFQName
            } else {
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
            let ownerFQName: [InternedString]
            if let receiverTypeID = propertyDecl.receiverType,
               let receiverType = ast.arena.typeRef(receiverTypeID),
               let resolvedOwner = fqName(
                   for: receiverType,
                   relativeTo: packageFQName,
                   topLevelNominalNames: topLevelNominalNames,
                   defaultImportedNameToPackage: defaultImportedNameToPackage,
                   ast: ast,
                   builtinNames: builtinNames,
                   interner: interner
               )
            {
                ownerFQName = resolvedOwner
            } else if propertyDecl.receiverType == nil {
                ownerFQName = packageFQName
            } else {
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
                constructorArities: bundledConstructorArities(of: classDecl),
                ownerFQName: ownerFQName,
                ast: ast,
                interner: interner,
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
                constructorArities: [],
                ownerFQName: ownerFQName,
                ast: ast,
                interner: interner,
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
                constructorArities: [],
                ownerFQName: ownerFQName,
                ast: ast,
                interner: interner,
                keys: &keys
            )

        default:
            break
        }
    }

    private static func bundledConstructorArities(of classDecl: ClassDecl) -> [Int] {
        var arities = classDecl.secondaryConstructors.map { $0.valueParams.count }
        if classDecl.hasPrimaryConstructorSyntax {
            arities.append(classDecl.primaryConstructorParams.count)
        }
        return arities
    }

    private static func collectBundledNominalMembers(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        companionObject: DeclID?,
        constructorArities: [Int],
        ownerFQName: [InternedString],
        ast: ASTModule,
        interner: StringInterner,
        keys: inout Set<BundledMemberKey>
    ) {
        let constructorName = interner.intern("<init>")
        for arity in constructorArities {
            keys.insert(
                BundledMemberKey(
                    ownerFQName: ownerFQName,
                    name: constructorName,
                    arity: arity
                )
            )
        }
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
                interner: interner,
                keys: &keys
            )
        }

        if let companionObject {
            collectBundledNestedDecl(
                declID: companionObject,
                ownerFQName: ownerFQName,
                ast: ast,
                interner: interner,
                keys: &keys
            )
        }
    }

    private static func collectBundledNestedDecl(
        declID: DeclID,
        ownerFQName: [InternedString],
        ast: ASTModule,
        interner: StringInterner,
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
                constructorArities: bundledConstructorArities(of: classDecl),
                ownerFQName: ownerFQName + [classDecl.name],
                ast: ast,
                interner: interner,
                keys: &keys
            )
        case let .interfaceDecl(interfaceDecl):
            collectBundledNominalMembers(
                memberFunctions: interfaceDecl.memberFunctions,
                memberProperties: interfaceDecl.memberProperties,
                nestedClasses: interfaceDecl.nestedClasses,
                nestedObjects: interfaceDecl.nestedObjects,
                companionObject: interfaceDecl.companionObject,
                constructorArities: [],
                ownerFQName: ownerFQName + [interfaceDecl.name],
                ast: ast,
                interner: interner,
                keys: &keys
            )
        case let .objectDecl(objectDecl):
            collectBundledNominalMembers(
                memberFunctions: objectDecl.memberFunctions,
                memberProperties: objectDecl.memberProperties,
                nestedClasses: objectDecl.nestedClasses,
                nestedObjects: objectDecl.nestedObjects,
                companionObject: nil,
                constructorArities: [],
                ownerFQName: ownerFQName + [objectDecl.name],
                ast: ast,
                interner: interner,
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
        defaultImportedNameToPackage: [InternedString: [InternedString]],
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
            // built-in root types (Int, Long, ...) and Kotlin's default-imported
            // top-level declarations (List, Sequence, ...) live under specific
            // packages regardless of which subpackage references them. Without
            // these checks, bundled extension declarations are keyed under the
            // wrong owner and the KSP-002 skip guard misses them.
            if path.count == 1, isBuiltinRootTypeName(first, builtinNames: builtinNames) {
                return [interner.intern("kotlin"), first]
            }
            if path.count == 1, let defaultPackage = defaultImportedNameToPackage[first] {
                return defaultPackage + path
            }
            // Nested types of default-imported top-level nominals (e.g.
            // CharProgression.Companion) must keep their default package prefix
            // so bundled companion-object extensions are keyed under the real owner.
            if path.count > 1, let defaultPackage = defaultImportedNameToPackage[first] {
                return defaultPackage + path
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
                defaultImportedNameToPackage: defaultImportedNameToPackage,
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

    private static func defaultImportMap(
        topLevelNominalNamesByPackage: [[InternedString]: Set<InternedString>],
        interner: StringInterner
    ) -> [InternedString: [InternedString]] {
        let kotlin = interner.intern("kotlin")
        let collections = interner.intern("collections")
        let sequences = interner.intern("sequences")
        let ranges = interner.intern("ranges")
        let text = interner.intern("text")
        let io = interner.intern("io")
        let native = interner.intern("native")

        let defaultImportPackages: [[InternedString]] = [
            [kotlin, collections],
            [kotlin, sequences],
            [kotlin, ranges],
            [kotlin, text],
            [kotlin, io],
            [kotlin],
            [kotlin, interner.intern("jvm")],
            [kotlin, native],
            [interner.intern("java"), interner.intern("lang")],
        ]

        // Compiler-provided synthetic types that are default-imported but not
        // declared in bundled .kt files. These must resolve to the same FQ name
        // as the symbol created later by HeaderHelpers so the KSP-002 skip guard
        // matches. Source-defined names take precedence below.
        let synthesizedNamesByPackage: [([InternedString], [String])] = [
            ([kotlin, collections], [
                "Iterable", "MutableIterable",
                "Collection", "MutableCollection",
                "List", "MutableList",
                "Set", "MutableSet",
                "Map", "MutableMap",
                "Iterator", "MutableIterator",
                "ListIterator", "MutableListIterator",
                "RandomAccess",
            ]),
            ([kotlin, sequences], ["Sequence"]),
            ([kotlin, ranges], [
                "ClosedRange", "OpenEndRange",
                "IntRange", "LongRange", "CharRange", "UIntRange", "ULongRange",
                "IntProgression", "LongProgression", "CharProgression",
                "UIntProgression", "ULongProgression",
            ]),
            ([kotlin, text], [
                "Regex", "MatchResult", "MatchGroup",
                "StringBuilder", "Appendable", "CharSequence",
            ]),
            ([kotlin, io], [
                "File", "InputStream", "OutputStream",
            ]),
            ([kotlin], [
                "Array",
                "ByteArray", "ShortArray", "IntArray", "LongArray",
                "FloatArray", "DoubleArray", "CharArray", "BooleanArray",
                "UByteArray", "UShortArray", "UIntArray", "ULongArray",
                "Pair", "Triple", "Result",
                "Throwable", "Exception", "Error", "RuntimeException",
            ]),
        ]

        var map: [InternedString: [InternedString]] = [:]

        for (pkg, names) in synthesizedNamesByPackage {
            for name in names {
                let interned = interner.intern(name)
                if map[interned] == nil {
                    map[interned] = pkg
                }
            }
        }

        for pkg in defaultImportPackages {
            let sourceNames = (topLevelNominalNamesByPackage[pkg] ?? [])
                .sorted { interner.resolve($0) < interner.resolve($1) }
            for name in sourceNames {
                map[name] = pkg
            }
        }

        return map
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

enum BundledSyntheticStubRegistration {
    private static let bundledIndexKey = "KSwiftK.BundledSyntheticStubRegistration.bundledIndex"
    private static let typesKey = "KSwiftK.BundledSyntheticStubRegistration.types"
    private static let skippedCountKey = "KSwiftK.BundledSyntheticStubRegistration.skippedCount"

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

    static func clear() {
        storage.removeObject(forKey: bundledIndexKey)
        storage.removeObject(forKey: typesKey)
        storage.removeObject(forKey: skippedCountKey)
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
