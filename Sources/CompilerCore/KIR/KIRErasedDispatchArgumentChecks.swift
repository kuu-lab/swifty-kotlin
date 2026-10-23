/// The runtime classifier required by an override whose parameter narrows an
/// erased dispatch slot. Generic arguments remain erased: `T : Foo` checks Foo,
/// not the concrete type argument used when constructing the receiver.
func kirErasedDispatchArgumentCastTarget(
    implementationType: TypeID,
    dispatchType: TypeID,
    sema: SemaModule,
    allowNonTypeParameterDispatchType: Bool = false
) -> TypeID? {
    if !allowNonTypeParameterDispatchType {
        guard case .typeParam = sema.types.kind(of: dispatchType) else {
            return nil
        }
    }

    func erasedUpperBound(_ type: TypeID) -> TypeID {
        var current = type
        var visited: Set<SymbolID> = []
        while case let .typeParam(parameter) = sema.types.kind(of: current) {
            guard visited.insert(parameter.symbol).inserted,
                  let bound = sema.symbols.typeParameterUpperBound(for: parameter.symbol)
            else {
                return sema.types.nullableAnyType
            }
            current = bound
        }
        return current
    }

    let target = erasedUpperBound(implementationType)
    switch sema.types.kind(of: target) {
    case .classType, .stringStruct, .functionType, .kClassType:
        break
    default:
        // Primitive representation changes are handled by the unboxing bridge.
        return nil
    }
    // A bridge checkcast checks the classifier and accepts null independently
    // of the implementation's non-null contract, preserving nullable bounds.
    let nullableTarget = sema.types.withNullability(.nullable, for: target)
    let dispatchBound = sema.types.withNullability(.nullable, for: erasedUpperBound(dispatchType))
    guard !sema.types.isSubtype(dispatchBound, nullableTarget) else {
        return nil
    }
    return nullableTarget
}

/// Whether a dispatch argument may be null after substituting its declared
/// type parameters. An unconstrained type parameter has the Kotlin default
/// upper bound `Any?` and therefore accepts null.
func kirErasedDispatchImplementationAcceptsNull(
    _ implementationType: TypeID,
    sema: SemaModule
) -> Bool {
    var current = implementationType
    var visited: Set<SymbolID> = []
    while case let .typeParam(parameter) = sema.types.kind(of: current) {
        if sema.types.nullability(of: current) == .nullable {
            return true
        }
        guard visited.insert(parameter.symbol).inserted,
              let bound = sema.symbols.typeParameterUpperBound(for: parameter.symbol)
        else {
            return true
        }
        current = bound
    }
    return sema.types.nullability(of: current) == .nullable
}
