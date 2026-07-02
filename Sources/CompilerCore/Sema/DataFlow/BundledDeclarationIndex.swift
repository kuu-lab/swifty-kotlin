/// Index of function and property declarations originating from bundled stdlib
/// Kotlin sources (`__bundled_*.kt`). Used by KSP-002 skip guards and KSP-003
/// duplicate-definition warnings when a synthetic stub slips past the guard.
struct BundledMemberKey: Hashable, Sendable {
    let ownerFQName: [InternedString]
    let name: InternedString
    let arity: Int
}

struct BundledDeclarationIndex: Sendable {
    static let empty = BundledDeclarationIndex(keys: [])

    private let keys: Set<BundledMemberKey>

    init(keys: Set<BundledMemberKey> = []) {
        self.keys = keys
    }

    func contains(_ key: BundledMemberKey) -> Bool {
        keys.contains(key)
    }

    func contains(ownerFQName: [InternedString], name: InternedString, arity: Int) -> Bool {
        contains(BundledMemberKey(ownerFQName: ownerFQName, name: name, arity: arity))
    }

    mutating func insert(_ key: BundledMemberKey) {
        self = BundledDeclarationIndex(keys: keys.union([key]))
    }

    static func build(
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> BundledDeclarationIndex {
        let bundledFileIDs = Set(
            sourceManager.fileIDs().filter { sourceManager.path(of: $0).hasPrefix("__bundled_") }
                .map(\.rawValue)
        )
        guard !bundledFileIDs.isEmpty else {
            return .empty
        }

        var keys: Set<BundledMemberKey> = []
        for symbol in symbols.allSymbols() {
            guard !symbol.flags.contains(.synthetic) else { continue }
            guard symbol.kind == .function || symbol.kind == .property else { continue }
            guard let declSite = symbol.declSite,
                  bundledFileIDs.contains(declSite.start.file.rawValue)
            else { continue }
            guard let key = memberKey(
                for: symbol,
                symbolID: symbol.id,
                symbols: symbols,
                types: types,
                interner: interner
            )
            else { continue }
            keys.insert(key)
        }
        return BundledDeclarationIndex(keys: keys)
    }

    static func memberKey(
        for symbol: SemanticSymbol,
        symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> BundledMemberKey? {
        guard symbol.kind == .function || symbol.kind == .property else { return nil }

        let arity: Int
        let receiverType: TypeID?
        if symbol.kind == .function {
            let signature = symbols.functionSignature(for: symbolID)
            arity = signature?.parameterTypes.count ?? 0
            receiverType = signature?.receiverType
        } else {
            arity = 0
            receiverType = symbols.extensionPropertyReceiverType(for: symbolID)
        }

        let ownerFQName = ownerFQName(
            declaredOwnerFQName: ownerFQName(for: symbol, symbolID: symbolID, symbols: symbols),
            receiverType: receiverType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        return BundledMemberKey(ownerFQName: ownerFQName, name: symbol.name, arity: arity)
    }

    static func ownerFQName(
        declaredOwnerFQName: [InternedString],
        receiverType: TypeID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [InternedString] {
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
        let nonNullType = types.makeNonNullable(receiverType)
        switch types.kind(of: nonNullType) {
        case let .classType(classType):
            return symbols.symbol(classType.classSymbol)?.fqName
        case let .primitive(primitive, _):
            return [interner.intern("kotlin"), interner.intern(primitive.kotlinName)]
        default:
            return nil
        }
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

    private static func classSymbol(for type: TypeID, types: TypeSystem) -> SymbolID? {
        let nonNullType = types.makeNonNullable(type)
        guard case let .classType(classType) = types.kind(of: nonNullType) else {
            return nil
        }
        return classType.classSymbol
    }
}

/// Active bundled-index context while `registerSyntheticDelegateStubs` runs.
enum BundledSyntheticStubRegistration {
    nonisolated(unsafe) static var bundledIndex: BundledDeclarationIndex = .empty
    nonisolated(unsafe) static var types: TypeSystem?
    nonisolated(unsafe) static var skippedCount: Int = 0
    /// When true, extension-member stub registration is deferred to the post-bundled pass.
    nonisolated(unsafe) static var preBundledPass: Bool = false
    /// When true, only extension-member stubs are registered (post-bundled pass).
    nonisolated(unsafe) static var postBundledPass: Bool = false

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
        guard bundledIndex.contains(key) else {
            return false
        }
        skippedCount += 1
        return true
    }
}
