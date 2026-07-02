/// Index of declarations originating from bundled stdlib Kotlin sources (`__bundled_*.kt`).
///
/// Used by synthetic stub registration to skip stubs when bundled Kotlin source
/// already provides the same API (owner FQName + member name + arity).
struct BundledDeclarationKey: Hashable {
    let ownerFQName: [InternedString]
    let name: InternedString
    let arity: Int
}

struct BundledDeclarationIndex {
    static let empty = BundledDeclarationIndex(keys: [])

    private let keys: Set<BundledDeclarationKey>

    init(keys: Set<BundledDeclarationKey>) {
        self.keys = keys
    }

    func contains(ownerFQName: [InternedString], name: InternedString, arity: Int) -> Bool {
        keys.contains(BundledDeclarationKey(ownerFQName: ownerFQName, name: name, arity: arity))
    }

    static func build(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> BundledDeclarationIndex {
        let kotlinCollections = interner.intern("kotlin")
        let collections = interner.intern("collections")
        let listName = interner.intern("List")
        let iterableName = interner.intern("Iterable")
        let listOwnerFQName: [InternedString] = [kotlinCollections, collections, listName]
        let iterableOwnerFQName: [InternedString] = [kotlinCollections, collections, iterableName]

        var keys = Set<BundledDeclarationKey>()

        func insert(ownerFQName: [InternedString], name: InternedString, arity: Int) {
            keys.insert(BundledDeclarationKey(ownerFQName: ownerFQName, name: name, arity: arity))
            if ownerFQName == listOwnerFQName {
                keys.insert(
                    BundledDeclarationKey(
                        ownerFQName: iterableOwnerFQName,
                        name: name,
                        arity: arity
                    )
                )
            }
        }

        for file in ast.sortedFiles {
            guard sourceManager.path(of: file.fileID).hasPrefix("__bundled_") else {
                continue
            }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID) else { continue }
                switch decl {
                case let .funDecl(funDecl):
                    let ownerFQName = extensionOwnerFQName(
                        packageFQName: file.packageFQName,
                        receiverTypeRefID: funDecl.receiverType,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner
                    ) ?? file.packageFQName
                    insert(
                        ownerFQName: ownerFQName,
                        name: funDecl.name,
                        arity: funDecl.valueParams.count
                    )

                case let .propertyDecl(propertyDecl):
                    let ownerFQName = extensionOwnerFQName(
                        packageFQName: file.packageFQName,
                        receiverTypeRefID: propertyDecl.receiverType,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner
                    ) ?? file.packageFQName
                    insert(ownerFQName: ownerFQName, name: propertyDecl.name, arity: 0)

                default:
                    continue
                }
            }
        }

        return BundledDeclarationIndex(keys: keys)
    }

    private static func extensionOwnerFQName(
        packageFQName: [InternedString],
        receiverTypeRefID: TypeRefID?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [InternedString]? {
        guard let receiverTypeRefID,
              let typeRef = ast.arena.typeRef(receiverTypeRefID)
        else {
            return nil
        }

        switch typeRef {
        case let .named(path, _, _):
            if path.count == 1 {
                return packageFQName + [path[0]]
            }
            return path

        case let .functionType(_, receiverRefID, _, _, _, _):
            return extensionOwnerFQName(
                packageFQName: packageFQName,
                receiverTypeRefID: receiverRefID,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            )

        default:
            return nil
        }
    }
}
