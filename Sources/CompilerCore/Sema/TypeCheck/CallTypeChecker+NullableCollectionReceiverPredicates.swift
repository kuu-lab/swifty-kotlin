/// Predicate for `isNullOrEmpty` on nullable collection receivers, consulted by
/// the member-call inference dispatcher.
extension CallTypeChecker {
    func isNullableCollectionIsNullOrEmptyReceiver(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        switch KnownCompilerNames(interner: interner).collectionKind(of: symbol) {
        case .map?, .set?, .array?, .list?, .collection?:
            return true
        case .sequence?, nil:
            return false
        }
    }
}
