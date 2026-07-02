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

    func contains(ownerFQName: [InternedString], name: InternedString, arity: Int) -> Bool {
        contains(owner: ownerFQName, name: name, arity: arity)
    }

    /// Build from AST bundled sources before SymbolTable header collection.
    /// Step (0) requires bundled SymbolTable registration before stubs; that reorder
    /// breaks sema until synthetic type foundations are split (KSP-002). AST scanning
    /// preserves compilation behavior while supplying `(owner, name, arity)` keys.
    static func build(ast: ASTModule, sourceManager: SourceManager) -> BundledDeclarationIndex {
        BundledDeclarationIndex(keys: buildKeys(ast: ast, sourceManager: sourceManager))
    }

    static func build(
        ast: ASTModule,
        symbols _: SymbolTable,
        types _: TypeSystem,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> BundledDeclarationIndex {
        var keys = buildKeys(ast: ast, sourceManager: sourceManager)
        addListIterableAliases(to: &keys, interner: interner)
        return BundledDeclarationIndex(keys: keys)
    }

    private static func buildKeys(ast: ASTModule, sourceManager: SourceManager) -> Set<BundledMemberKey> {
        let bundledFiles = ast.sortedFiles.filter {
            sourceManager.path(of: $0.fileID).hasPrefix("__bundled_")
        }
        let topLevelNominalNamesByPackage = collectTopLevelNominalNamesByPackage(
            files: bundledFiles,
            ast: ast
        )

        var keys: Set<BundledMemberKey> = []
        for file in bundledFiles {
            let topLevelNominalNames = topLevelNominalNamesByPackage[file.packageFQName] ?? []
            for declID in file.topLevelDecls {
                collectBundledTopLevelDecl(
                    declID: declID,
                    packageFQName: file.packageFQName,
                    topLevelNominalNames: topLevelNominalNames,
                    ast: ast,
                    keys: &keys
                )
            }
        }
        return keys
    }

    /// Build from SymbolTable symbols whose `declSite` is in bundled virtual files.
    static func build(sourceManager: SourceManager, symbols: SymbolTable, types: TypeSystem) -> BundledDeclarationIndex {
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

            let ownerFQName: [InternedString]?
            let arity: Int
            switch symbol.kind {
            case .function:
                guard let signature = symbols.functionSignature(for: symbol.id) else {
                    continue
                }
                if let receiverType = signature.receiverType {
                    ownerFQName = nominalOwnerFQName(for: receiverType, symbols: symbols, types: types)
                } else if let parentID = symbols.parentSymbol(for: symbol.id),
                          let parentSymbol = symbols.symbol(parentID)
                {
                    ownerFQName = parentSymbol.fqName
                } else {
                    ownerFQName = nil
                }
                arity = signature.parameterTypes.count
            case .property, .field:
                if let receiverType = symbols.extensionPropertyReceiverType(for: symbol.id) {
                    ownerFQName = nominalOwnerFQName(for: receiverType, symbols: symbols, types: types)
                } else if let parentID = symbols.parentSymbol(for: symbol.id),
                          let parentSymbol = symbols.symbol(parentID)
                {
                    ownerFQName = parentSymbol.fqName
                } else {
                    ownerFQName = nil
                }
                arity = 0
            default:
                continue
            }

            guard let ownerFQName else {
                continue
            }

            keys.insert(
                BundledMemberKey(
                    ownerFQName: ownerFQName,
                    name: symbol.name,
                    arity: arity
                )
            )
        }

        return BundledDeclarationIndex(keys: keys)
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
                    ast: ast
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
                    ast: ast
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
        ast: ASTModule
    ) -> [InternedString]? {
        switch typeRef {
        case let .named(path, _, _):
            guard let first = path.first else {
                return nil
            }
            if pathStarts(with: path, prefix: packageFQName) {
                return path
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
                ast: ast
            )
        case .functionType, .intersection:
            return nil
        }
    }

    private static func nominalOwnerFQName(
        for typeID: TypeID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [InternedString]? {
        switch types.kind(of: types.makeNonNullable(typeID)) {
        case let .classType(nominalType):
            guard let symbol = symbols.symbol(nominalType.classSymbol) else {
                return nil
            }
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                return symbol.fqName
            default:
                return nil
            }
        default:
            return nil
        }
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
