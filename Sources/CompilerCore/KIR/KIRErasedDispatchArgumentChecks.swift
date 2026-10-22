/// The runtime classifier required by an override whose parameter narrows an
/// erased dispatch slot. Generic arguments remain erased: `T : Foo` checks Foo,
/// not the concrete type argument used when constructing the receiver.
func kirErasedDispatchArgumentCastTarget(
    implementationType: TypeID,
    dispatchType: TypeID,
    sema: SemaModule
) -> TypeID? {
    guard case .typeParam = sema.types.kind(of: dispatchType) else {
        return nil
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

/// The value a JVM type-safe barrier returns when an erased collection
/// argument fails its `instanceof` check. Kotlin emits these defaults for the
/// special-builtins collection members whose erased `Object` signature would
/// otherwise invoke an implementation declared against a narrower parameter.
enum KIRSpecialBuiltinBarrierDefault {
    case booleanFalse
    case indexNegativeOne
    case nullValue
}

/// Default value attached to a collection interface member that JVM treats as
/// a special builtin, or nil when the member has no type-safe barrier.
/// Mirrors the barrier list in the Kotlin compiler's
/// `TypeSafeBarrierDescription` coverage: only the single-argument erased
/// members below carry a default-valued barrier.
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

/// The runtime type an erased collection bridge argument must satisfy before
/// it may reach the implementation parameter, or nil when the parameter
/// admits every value the erased slot can carry. The target is the parameter's
/// own erased type kept non-nullable: `Nothing` stays `Nothing` so its token
/// never matches (JVM's `instanceof Void` never passes), and a parameter
/// erased to a nullable bound such as `Any?` admits null, matching the JVM
/// behaviour of invoking the implementation directly (Kotlin's own
/// `AbstractMap.containsKey` accepts null keys exactly this way).
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
