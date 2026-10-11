import RuntimeABI

/// Element-type extraction for Collection member-call fallbacks
/// (incl. primitive arrays and range receivers).
///
/// Split out from `CallTypeChecker+CollectionMemberFallback.swift`.
extension CallTypeChecker {
    private func collectionFallbackClassTypes(
        _ type: TypeID,
        sema: SemaModule,
        visitedTypeParams: inout Set<SymbolID>
    ) -> [(classType: ClassType, symbol: SemanticSymbol)] {
        let nonNullType = sema.types.makeNonNullable(type)
        switch sema.types.kind(of: nonNullType) {
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol) else {
                return []
            }
            return [(classType, symbol)]
        case let .intersection(parts):
            return parts.flatMap {
                collectionFallbackClassTypes($0, sema: sema, visitedTypeParams: &visitedTypeParams)
            }
        case let .typeParam(typeParam):
            guard visitedTypeParams.insert(typeParam.symbol).inserted else {
                return []
            }
            return sema.symbols.typeParameterUpperBounds(for: typeParam.symbol).flatMap {
                collectionFallbackClassTypes($0, sema: sema, visitedTypeParams: &visitedTypeParams)
            }
        default:
            return []
        }
    }

    private func collectionFallbackClassTypes(
        _ type: TypeID,
        sema: SemaModule
    ) -> [(classType: ClassType, symbol: SemanticSymbol)] {
        var visitedTypeParams: Set<SymbolID> = []
        return collectionFallbackClassTypes(type, sema: sema, visitedTypeParams: &visitedTypeParams)
    }

    func collectionFallbackElementType(receiverID: ExprID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let rangeReceiverKind = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        )
        if (rangeReceiverKind == .intRange || rangeReceiverKind == .intProgression),
           let sourceLevelRangeReceiverType = sourceLevelRangeMemberLookupType(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ),
           let rangeElementType = driver.helpers.iterableElementType(
               for: sourceLevelRangeReceiverType,
               isRangeExpr: true,
               isCharRangeExpr: sema.bindings.isCharRangeExpr(receiverID),
               sema: sema,
               interner: interner
           )
        {
            return rangeElementType
        }
        guard let (classType, symbol) = collectionFallbackClassTypes(receiverType, sema: sema).first else {
            return sema.types.anyType
        }
        if knownNames.isMapLikeSymbol(symbol),
           classType.args.count == 2
        {
            let keyType = switch classType.args[0] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let valueType = switch classType.args[1] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let entrySymbol = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsMapEntryFQName)
            guard let entrySymbol else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: entrySymbol,
                args: [.out(keyType), .out(valueType)],
                nullability: .nonNull
            )))
        }

        guard let firstArg = classType.args.first else {
            // Primitive arrays (IntArray, DoubleArray, ...) have no type argument;
            // their element type comes from the class itself (BUG-158: a
            // `joinToString(..., transform)` lambda must see the real element type
            // rather than an erased `Any`).
            return primitiveArrayElementType(
                className: symbol.name,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
    }
}
