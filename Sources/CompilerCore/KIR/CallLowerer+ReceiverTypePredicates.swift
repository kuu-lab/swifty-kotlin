/// Receiver-type predicate helpers used by CallLowerer to dispatch
/// member-call lowerings (Regex / StringBuilder / Sequence / Iterable /
/// Collection / Map / Set / Array / Grouping etc.).
///
/// Split out from `CallLowerer+MemberCalls.swift` so that the dispatcher
/// file stays focused on lowering control flow.
extension CallLowerer {
    func isRegexLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        ReceiverClassifier(sema: sema, interner: interner).isRegexLikeType(receiverType)
    }

    /// Check whether a type is Sequence-like (for member-call and operator
    /// lowering decisions).  Shared across `CallLowerer+MemberCalls` and
    /// `CallLowerer+Operators`; kept `internal` to avoid exposing it beyond
    /// the `CallLowerer` extensions.
    func isSequenceLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        ReceiverClassifier(sema: sema, interner: interner).isSequenceLikeType(receiverType)
    }

    func isIterableOrCollectionInterfaceType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        let symbolName = interner.resolve(symbol.name)
        return symbolName == "Iterable" || symbolName == "Collection"
    }

    func toMutableListRuntimeCalleeForSequenceOrIterableFallback(
        useIterableFallback: Bool,
        interner: StringInterner
    ) -> InternedString {
        interner.intern(useIterableFallback ? "__kk_collection_toMutableList" : "kk_sequence_toMutableList")
    }

    func isConcreteListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        // Preserve KIR's historical name-only matching; the stricter Sema
        // overload predicate also checks for one type argument.
        ReceiverClassifier(sema: sema, interner: interner).isListLikeType(receiverType)
    }

    func collectionSelectorPrimitiveCompareKind(
        of selectorExpr: ExprID?,
        sema: SemaModule
    ) -> PrimitiveCompareABIKind? {
        guard let selectorExpr,
              let selectorType = sema.bindings.exprTypes[selectorExpr]
        else {
            return nil
        }
        switch sema.types.kind(of: sema.types.makeNonNullable(selectorType)) {
        case let .functionType(functionType):
            return primitiveCompareABIKind(for: functionType.returnType, sema: sema)
        default:
            return nil
        }
    }


    func isMutableSetLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        ReceiverClassifier(sema: sema, interner: interner).isMutableSetLikeType(receiverType)
    }

    func isConcreteCollectionLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        ReceiverClassifier(sema: sema, interner: interner).isConcreteCollectionLikeType(receiverType)
    }

    func isConcreteArrayLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        ReceiverClassifier(sema: sema, interner: interner).isConcreteArrayLikeType(receiverType)
    }

    func isGenericKotlinArrayType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return symbol.fqName == [interner.intern("kotlin"), interner.intern("Array")]
    }

    func isSetLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        ReceiverClassifier(sema: sema, interner: interner).isSetLikeType(receiverType)
    }
}
