/// Compiler-owned top-level collection factories that still have a dedicated
/// KIR lowering path. The table deliberately contains only the declarations
/// whose exact SymbolID is used by that path; source-backed helpers such as
/// `listOfNotNull` remain ordinary Kotlin calls.
enum WellKnownCollectionFactory: CaseIterable, Hashable, Sendable {
    case emptyList
    case listOf
    case mutableListOf
    case arrayListOf
    case emptySet
    case setOf
    case setOfNotNull
    case mutableSetOf
    case hashSetOf
    case linkedSetOf
    case emptyMap
    case mapOf
    case mutableMapOf
    case hashMapOf
    case linkedMapOf

    var simpleName: String {
        switch self {
        case .emptyList: "emptyList"
        case .listOf: "listOf"
        case .mutableListOf: "mutableListOf"
        case .arrayListOf: "arrayListOf"
        case .emptySet: "emptySet"
        case .setOf: "setOf"
        case .setOfNotNull: "setOfNotNull"
        case .mutableSetOf: "mutableSetOf"
        case .hashSetOf: "hashSetOf"
        case .linkedSetOf: "linkedSetOf"
        case .emptyMap: "emptyMap"
        case .mapOf: "mapOf"
        case .mutableMapOf: "mutableMapOf"
        case .hashMapOf: "hashMapOf"
        case .linkedMapOf: "linkedMapOf"
        }
    }
}

/// Compiler-owned enum entry/value intrinsics. `enumEntriesIntrinsic` is the
/// internal source-level entry point used by the bundled enum implementation.
enum WellKnownEnumIntrinsic: CaseIterable, Hashable, Sendable {
    case enumValues
    case enumValueOf
    case enumEntries
    case enumEntriesIntrinsic

    var fqNameParts: [String] {
        switch self {
        case .enumValues, .enumValueOf:
            ["kotlin", simpleName]
        case .enumEntries, .enumEntriesIntrinsic:
            ["kotlin", "enums", simpleName]
        }
    }

    private var simpleName: String {
        switch self {
        case .enumValues: "enumValues"
        case .enumValueOf: "enumValueOf"
        case .enumEntries: "enumEntries"
        case .enumEntriesIntrinsic: "enumEntriesIntrinsic"
        }
    }
}

private enum WellKnownSymbol: Hashable, Sendable {
    case collectionFactory(WellKnownCollectionFactory)
    case enumIntrinsic(WellKnownEnumIntrinsic)

    static var all: [WellKnownSymbol] {
        WellKnownCollectionFactory.allCases.map { .collectionFactory($0) }
            + WellKnownEnumIntrinsic.allCases.map { .enumIntrinsic($0) }
    }

    var fqNameParts: [String] {
        switch self {
        case let .collectionFactory(factory):
            ["kotlin", "collections", factory.simpleName]
        case let .enumIntrinsic(intrinsic):
            intrinsic.fqNameParts
        }
    }
}

/// ARCH-021: resolves the small set of compiler-owned special declarations
/// once, after header collection. Consumers compare exact SymbolIDs instead
/// of re-deriving ownership from short names and package strings.
struct WellKnownSymbols: Sendable {
    static let empty = WellKnownSymbols(symbolByID: [:])

    private let symbolByID: [SymbolID: WellKnownSymbol]

    private init(symbolByID: [SymbolID: WellKnownSymbol]) {
        self.symbolByID = symbolByID
    }

    init(symbols: SymbolTable, interner: StringInterner, sourceManager: SourceManager) {
        var symbolByID: [SymbolID: WellKnownSymbol] = [:]
        for knownSymbol in WellKnownSymbol.all {
            let fqName = knownSymbol.fqNameParts.map(interner.intern)
            for symbolID in symbols.lookupAll(fqName: fqName) {
                guard let symbol = symbols.symbol(symbolID),
                      symbol.kind == .function,
                      Self.isCompilerOwned(symbol, symbols: symbols, sourceManager: sourceManager)
                else {
                    continue
                }
                symbolByID[symbolID] = knownSymbol
            }
        }
        self.init(symbolByID: symbolByID)
    }

    private static func isCompilerOwned(
        _ symbol: SemanticSymbol,
        symbols: SymbolTable,
        sourceManager: SourceManager
    ) -> Bool {
        if symbol.flags.contains(.synthetic) || symbol.flags.contains(.importedLibrary) {
            return true
        }
        let fileID = symbols.sourceFileID(for: symbol.id) ?? symbol.declSite?.start.file
        return fileID.flatMap { sourceManager.origin(of: $0)?.isBundledStdlib } == true
    }

    func collectionFactory(for symbol: SymbolID?) -> WellKnownCollectionFactory? {
        guard let symbol,
              case let .collectionFactory(factory) = symbolByID[symbol]
        else {
            return nil
        }
        return factory
    }

    func enumIntrinsic(for symbol: SymbolID?) -> WellKnownEnumIntrinsic? {
        guard let symbol,
              case let .enumIntrinsic(intrinsic) = symbolByID[symbol]
        else {
            return nil
        }
        return intrinsic
    }
}
