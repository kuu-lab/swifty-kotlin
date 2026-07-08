struct ReceiverClassification {
    let receiverType: TypeID
    let isArrayReceiver: Bool
    let isIterableReceiver: Bool
    let isCollectionReceiver: Bool
    let isSequenceReceiver: Bool
    let isMapReceiver: Bool
    let isSetReceiver: Bool
    let isListReceiver: Bool
    let isMutableCollectionReceiver: Bool
    let isMutableListReceiver: Bool
    let isMutableSetReceiver: Bool
    let isMutableMapReceiver: Bool
    let isListFactoryReceiver: Bool
    let isSyntheticSequenceReceiver: Bool
}

struct ReceiverClassifier {
    let sema: SemaModule
    let interner: StringInterner

    func classify(
        receiverID: ExprID,
        receiverType explicitReceiverType: TypeID? = nil,
        ast: ASTModule? = nil
    ) -> ReceiverClassification {
        let receiverType = explicitReceiverType ?? sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let isCollectionExpr = sema.bindings.isCollectionExpr(receiverID)
        let isListFactoryReceiver = ast.map {
            isListCollectionFactoryReceiver(receiverID: receiverID, ast: $0)
        } ?? false
        let isCollectionType = isCollectionLikeType(receiverType)
        let isMapReceiver = isMapLikeCollectionType(receiverType)
        let isSyntheticSequenceReceiver = isCollectionExpr
            && !isCollectionType
            && !isMapReceiver
            && !isListFactoryReceiver
        return ReceiverClassification(
            receiverType: receiverType,
            isArrayReceiver: isArrayLikeType(receiverType),
            isIterableReceiver: isIterableLikeType(receiverType),
            isCollectionReceiver: isCollectionExpr || isCollectionType,
            isSequenceReceiver: isSequenceLikeType(receiverType) || isSyntheticSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetLikeCollectionType(receiverType),
            isListReceiver: isConcreteListLikeCollectionType(receiverType),
            isMutableCollectionReceiver: isMutableCollectionType(receiverType),
            isMutableListReceiver: isMutableListCollectionType(receiverType),
            isMutableSetReceiver: isMutableSetType(receiverType),
            isMutableMapReceiver: isMutableMapType(receiverType),
            isListFactoryReceiver: isListFactoryReceiver,
            isSyntheticSequenceReceiver: isSyntheticSequenceReceiver
        )
    }

    func isArrayLikeReceiver(receiverID: ExprID) -> Bool {
        isArrayLikeType(receiverType(for: receiverID))
    }

    func isArrayLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isArrayLikeName(symbol.name)
    }

    func isCollectionLikeReceiver(receiverID: ExprID) -> Bool {
        if sema.bindings.isCollectionExpr(receiverID) {
            return true
        }
        return isCollectionLikeType(receiverType(for: receiverID))
    }

    func isIterableLikeReceiver(receiverID: ExprID) -> Bool {
        isIterableLikeType(receiverType(for: receiverID))
    }

    func isIterableLikeType(_ type: TypeID) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return symbol.name == interner.intern("Iterable")
            || symbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
    }

    func isSequenceLikeReceiver(receiverID: ExprID) -> Bool {
        isSequenceLikeType(receiverType(for: receiverID))
    }

    func isSequenceLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isSequenceSymbol(symbol)
    }

    func isCollectionLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isCollectionLikeSymbol(symbol)
    }

    func isListLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol)
    }

    func isConcreteListLikeType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && classType.args.count == 1
    }

    func isMapLikeCollectionReceiver(receiverID: ExprID) -> Bool {
        isMapLikeCollectionType(receiverType(for: receiverID))
    }

    func isMapLikeCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol) && classType.args.count == 2
    }

    func isMutableListType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let symbol = nominalSymbol(of: sema.types.makeNonNullable(type)) else {
            return false
        }
        return symbol.name == knownNames.mutableList
            || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
    }

    func isMutableCollectionReceiver(receiverID: ExprID) -> Bool {
        isMutableCollectionType(receiverType(for: receiverID))
    }

    func isMutableCollectionType(_ type: TypeID) -> Bool {
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return (
            symbol.name == interner.intern("MutableCollection")
                || symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableCollection"),
                ]
        ) && classType.args.count == 1
    }

    func isMutableListCollectionReceiver(receiverID: ExprID) -> Bool {
        isMutableListCollectionType(receiverType(for: receiverID))
    }

    func isMutableListCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return (
            symbol.name == knownNames.mutableList
                || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
        ) && classType.args.count == 1
    }

    func isMutableSetReceiver(receiverID: ExprID) -> Bool {
        isMutableSetType(receiverType(for: receiverID))
    }

    func isMutableSetType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isMutableSetSymbol(symbol) && classType.args.count == 1
    }

    func isMutableMapReceiver(receiverID: ExprID) -> Bool {
        isMutableMapType(receiverType(for: receiverID))
    }

    func isMutableMapType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isMutableMapSymbol(symbol) && classType.args.count == 2
    }

    func isConcreteListLikeCollectionReceiver(receiverID: ExprID) -> Bool {
        isConcreteListLikeCollectionType(receiverType(for: receiverID))
    }

    func isConcreteListLikeCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && !knownNames.isMapLikeSymbol(symbol)
    }

    func isSetLikeCollectionReceiver(receiverID: ExprID) -> Bool {
        isSetLikeCollectionType(receiverType(for: receiverID))
    }

    func isSetLikeCollectionType(_ type: TypeID) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return knownNames.collectionKind(of: symbol) == .set && classType.args.count == 1
    }

    func isListCollectionFactoryReceiver(receiverID: ExprID, ast: ASTModule) -> Bool {
        guard sema.bindings.isCollectionExpr(receiverID),
              let expr = ast.arena.expr(receiverID),
              case .call(let calleeID, _, _, _) = expr,
              let calleeExpr = ast.arena.expr(calleeID),
              case .nameRef(let name, _) = calleeExpr
        else {
            return false
        }
        return name == interner.intern("listOf")
            || name == interner.intern("listOfNotNull")
            || name == interner.intern("emptyList")
            || name == interner.intern("mutableListOf")
            || name == interner.intern("arrayListOf")
    }

    private func receiverType(for receiverID: ExprID) -> TypeID {
        sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
    }

    private func nominalSymbol(of type: TypeID) -> SemanticSymbol? {
        switch sema.types.kind(of: type) {
        case let .classType(classType):
            return sema.symbols.symbol(classType.classSymbol)
        case let .intersection(parts):
            for part in parts {
                if let symbol = nominalSymbol(of: part) {
                    return symbol
                }
            }
            return nil
        default:
            return nil
        }
    }
}

extension CallTypeChecker {
    func receiverClassifier(sema: SemaModule, interner: StringInterner) -> ReceiverClassifier {
        ReceiverClassifier(sema: sema, interner: interner)
    }

    func isArrayLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isArrayLikeReceiver(receiverID: receiverID)
    }

    func isMutableListType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isMutableListType(type)
    }

    func isMapLikeCollectionType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isMapLikeCollectionType(type)
    }

    func isConcreteListLikeType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isConcreteListLikeType(type)
    }

    func isCollectionLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isCollectionLikeReceiver(receiverID: receiverID)
    }

    func isIterableLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isIterableLikeReceiver(receiverID: receiverID)
    }

    func isSequenceLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isSequenceLikeType(receiverType)
    }

    func isCollectionLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isCollectionLikeType(receiverType)
    }

    func isListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isListLikeType(receiverType)
    }

    func isListCollectionFactoryReceiver(
        receiverID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        receiverClassifier(sema: sema, interner: interner).isListCollectionFactoryReceiver(
            receiverID: receiverID,
            ast: ast
        )
    }
}
