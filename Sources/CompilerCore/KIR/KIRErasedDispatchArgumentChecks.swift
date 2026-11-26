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
        var current = kirDefinitelyNotNullTypeParameter(of: type, sema: sema) ?? type
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
    let targetIsPrimitive: Bool
    switch sema.types.kind(of: target) {
    case .classType, .stringStruct, .functionType, .kClassType:
        targetIsPrimitive = false
    case .nothing:
        targetIsPrimitive = false
    case .primitive:
        // KUU-3172: the unboxing bridge alone is not enough for primitive
        // parameters — `kk_unbox_int` & friends pass a wrong-type object
        // through unchanged, so `Base<T>.foo(x: T)` overridden as
        // `foo(x: Int)` silently forwarded any reference argument where
        // the JVM bridge's `checkcast Integer` throws ClassCastException.
        targetIsPrimitive = true
    default:
        return nil
    }
    // A bridge checkcast checks the classifier and accepts null independently
    // of the implementation's non-null contract, preserving nullable bounds —
    // except for primitive targets, whose unboxed representation cannot carry
    // the null sentinel: a null slipping through the cast would unbox to a
    // bogus value rather than reach code that still observes it as null.
    // Honoring the parameter's null contract there matches the JVM bridge's
    // unbox call, which NPEs on a null argument (KUU-3172).
    let nullableTarget = targetIsPrimitive
        && !kirErasedDispatchImplementationAcceptsNull(implementationType, sema: sema)
        ? sema.types.withNullability(.nonNull, for: target)
        : sema.types.withNullability(.nullable, for: target)
    let dispatchBound = sema.types.withNullability(.nullable, for: erasedUpperBound(dispatchType))
    guard !sema.types.isSubtype(dispatchBound, nullableTarget) else {
        return nil
    }
    return nullableTarget
}

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

enum KIRSpecialBuiltinBarrierDefault {
    case booleanFalse
    case indexNegativeOne
    case nullValue
}

func kirSpecialBuiltinBarrierDefault(
    for interfaceMethod: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> KIRSpecialBuiltinBarrierDefault? {
    guard let method = sema.symbols.symbol(interfaceMethod),
          method.kind == .function,
          method.fqName.count == 4,
          interner.resolve(method.fqName[0]) == "kotlin",
          interner.resolve(method.fqName[1]) == "collections",
          sema.symbols.functionSignature(for: interfaceMethod)?.parameterTypes.count == 1
    else {
        return nil
    }
    let owner = interner.resolve(method.fqName[2])
    let name = interner.resolve(method.fqName[3])
    switch (owner, name) {
    case ("Collection", "contains"), ("Collection", "containsAll"),
         ("Set", "contains"),
         ("MutableCollection", "remove"), ("MutableCollection", "removeAll"), ("MutableCollection", "retainAll"),
         ("MutableSet", "remove"), ("MutableSet", "removeAll"), ("MutableSet", "retainAll"),
         ("MutableList", "remove"), ("MutableList", "removeAll"), ("MutableList", "retainAll"),
         ("Map", "containsKey"), ("Map", "containsValue"):
        return .booleanFalse
    case ("List", "indexOf"), ("List", "lastIndexOf"):
        return .indexNegativeOne
    case ("Map", "get"), ("MutableMap", "remove"):
        return .nullValue
    default:
        return nil
    }
}

func kirErasedDispatchBarrierCheckType(
    implementationParamType: TypeID,
    sema: SemaModule
) -> TypeID? {
    guard sema.types.kind(of: implementationParamType) != .error else {
        return nil
    }
    var current = implementationParamType
    var visited: Set<SymbolID> = []
    while case let .typeParam(parameter) = sema.types.kind(of: current) {
        guard visited.insert(parameter.symbol).inserted,
              let bound = sema.symbols.typeParameterUpperBound(for: parameter.symbol)
        else {
            return nil
        }
        current = bound
    }
    guard sema.types.nullability(of: current) != .nullable else {
        return nil
    }
    return current
}
