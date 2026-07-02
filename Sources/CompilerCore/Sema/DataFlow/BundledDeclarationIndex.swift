import Foundation

/// Index of member declarations originating from bundled stdlib virtual sources (`__bundled_*.kt`).
struct BundledDeclarationIndex {
    static let empty = BundledDeclarationIndex(keys: [])

    private struct BundledMemberKey: Hashable {
        let ownerFQName: [InternedString]
        let name: InternedString
        let arity: Int
    }

    private let keys: Set<BundledMemberKey>

    private init(keys: Set<BundledMemberKey>) {
        self.keys = keys
    }

    func contains(owner: [InternedString], name: InternedString, arity: Int) -> Bool {
        keys.contains(BundledMemberKey(ownerFQName: owner, name: name, arity: arity))
    }

    static func build(sourceManager: SourceManager, symbols: SymbolTable) -> BundledDeclarationIndex {
        let bundledFileIDs = Set(
            sourceManager.fileIDs()
                .filter { sourceManager.path(of: $0).hasPrefix("__bundled_") }
                .map(\.rawValue)
        )
        guard !bundledFileIDs.isEmpty else {
            return .empty
        }

        var keys: Set<BundledMemberKey> = []
        for symbol in symbols.allSymbols() {
            guard let declSite = symbol.declSite,
                  bundledFileIDs.contains(declSite.start.file.rawValue)
            else {
                continue
            }

            switch symbol.kind {
            case .function, .property, .field:
                break
            default:
                continue
            }

            guard let parentID = symbols.parentSymbol(for: symbol.id),
                  let parentSymbol = symbols.symbol(parentID)
            else {
                continue
            }

            let arity: Int
            switch symbol.kind {
            case .function:
                arity = symbols.functionSignature(for: symbol.id)?.parameterTypes.count ?? 0
            case .property, .field:
                arity = 0
            default:
                continue
            }

            keys.insert(
                BundledMemberKey(
                    ownerFQName: parentSymbol.fqName,
                    name: symbol.name,
                    arity: arity
                )
            )
        }

        return BundledDeclarationIndex(keys: keys)
    }
}
