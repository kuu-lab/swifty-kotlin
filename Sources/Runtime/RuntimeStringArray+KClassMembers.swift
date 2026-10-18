import Foundation
import RuntimeABI


@_cdecl("__kk_kclass_isInstance")
public func __kk_kclass_isInstance(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return 0
    }
    return kk_op_is(valueRaw, box.typeToken)
}

/// Called during module initialization to attach compile-time member data.
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass returned by `__kk_kclass_create`.
///   - memberRaw: Opaque handle to the member callable (KFunction or KPropertyStub).
/// - Returns: 0 on success.
@_cdecl("__kk_kclass_register_member")
public func __kk_kclass_register_member(_ kclassRaw: Int, _ memberRaw: Int) -> Int {
    runtimeKMemberRegistry.register(classRaw: kclassRaw, memberRaw: memberRaw)
    return 0
}

@_cdecl("__kk_kclass_members")
public func __kk_kclass_members(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.members(for: kclassRaw)))
}

/// Only constructors registered through `__kk_kconstructor_create` are returned.
@_cdecl("__kk_kclass_constructors")
public func __kk_kclass_constructors(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKConstructorRegistry.constructors(for: kclassRaw)))
}

/// Nested classes are attached per parent type token via
/// `__kk_kclass_register_nested_class` (KUU-1357 / MIGRATION-REFLECT-002).
@_cdecl("__kk_kclass_nested_classes")
public func __kk_kclass_nested_classes(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = runtimeKNestedClassRegistry.nestedClasses(for: box.typeToken).map {
        __kk_kclass_create($0.token, $0.nameRaw)
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

/// Emitted during class reflection metadata setup.
@_cdecl("__kk_kclass_register_companion")
public func __kk_kclass_register_companion(
    _ typeToken: Int,
    _ companionToken: Int,
    _ companionNameRaw: Int
) -> Int {
    runtimeKCompanionRegistry.register(
        typeToken: typeToken,
        companionToken: companionToken,
        companionNameRaw: companionNameRaw
    )
    return 0
}

@_cdecl("__kk_kclass_companion_object")
public func __kk_kclass_companion_object(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let entry = runtimeKCompanionRegistry.companion(for: box.typeToken)
    else {
        return runtimeNullSentinelInt
    }
    return __kk_kclass_create(entry.token, entry.nameRaw)
}

/// Emitted once per nested class during class reflection metadata
/// setup (KUU-1357 / MIGRATION-REFLECT-002).
@_cdecl("__kk_kclass_register_nested_class")
public func __kk_kclass_register_nested_class(
    _ typeToken: Int,
    _ nestedToken: Int,
    _ nestedNameRaw: Int
) -> Int {
    runtimeKNestedClassRegistry.register(
        typeToken: typeToken,
        nestedToken: nestedToken,
        nestedNameRaw: nestedNameRaw
    )
    return 0
}

@_cdecl("__kk_kclass_primary_constructor")
public func __kk_kclass_primary_constructor(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return runtimeNullSentinelInt
    }
    return runtimeKConstructorRegistry.primaryConstructor(for: kclassRaw) ?? runtimeNullSentinelInt
}


/// Returns registered `RuntimeKPropertyStub` handles only.
@_cdecl("__kk_kclass_properties")
public func __kk_kclass_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

@_cdecl("__kk_kclass_member_properties")
public func __kk_kclass_member_properties(_ kclassRaw: Int) -> Int {
    __kk_kclass_properties(kclassRaw)
}

@_cdecl("__kk_kclass_declared_member_properties")
public func __kk_kclass_declared_member_properties(_ kclassRaw: Int) -> Int {
    __kk_kclass_properties(kclassRaw)
}

/// Returns registered `RuntimeKFunctionBox` handles only.
@_cdecl("__kk_kclass_functions")
public func __kk_kclass_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

@_cdecl("__kk_kclass_member_functions")
public func __kk_kclass_member_functions(_ kclassRaw: Int) -> Int {
    __kk_kclass_functions(kclassRaw)
}

@_cdecl("__kk_kclass_declared_member_functions")
public func __kk_kclass_declared_member_functions(_ kclassRaw: Int) -> Int {
    __kk_kclass_functions(kclassRaw)
}


/// Casts `valueRaw` to the type represented by this KClass.
/// If the value is an instance of the type, returns it unchanged.
/// If not, sets `outThrown` to a `ClassCastException` and returns the null sentinel.
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass.
///   - valueRaw: The value to cast.
///   - outThrown: Out-pointer for the thrown exception (nullable).
/// - Returns: `valueRaw` on success, or `runtimeNullSentinelInt` on failure.
@_cdecl("__kk_kclass_cast")
public func __kk_kclass_cast(
    _ kclassRaw: Int,
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        outThrown?.pointee = runtimeAllocateClassCastException(
            message: "Invalid KClass handle."
        )
        return runtimeNullSentinelInt
    }
    let isInstance = kk_op_is(valueRaw, box.typeToken)
    if isInstance != 0 {
        return valueRaw
    }
    let typeName: String
    if let metadata = box.metadata {
        typeName = metadata.qualifiedName.isEmpty ? metadata.simpleName : metadata.qualifiedName
    } else {
        typeName = "Unknown"
    }
    outThrown?.pointee = runtimeAllocateClassCastException(
        message: "Value cannot be cast to \(typeName)."
    )
    return runtimeNullSentinelInt
}

/// Never throws; equivalent to Kotlin's `safeCast` (`value as? T`).
@_cdecl("__kk_kclass_safeCast")
public func __kk_kclass_safeCast(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    let isInstance = kk_op_is(valueRaw, box.typeToken)
    return isInstance != 0 ? valueRaw : runtimeNullSentinelInt
}
