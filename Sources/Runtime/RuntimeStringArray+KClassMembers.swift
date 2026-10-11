import Foundation
import RuntimeABI

// MARK: - REFL-005: KClass.isInstance, members, constructors

/// Checks if a value is an instance of the type represented by this KClass.
/// Delegates to the existing `kk_op_is` runtime type check using the KClass
/// box's type token.
/// Returns 1 (true) if the value is an instance, 0 (false) otherwise.
@_cdecl("__kk_kclass_isInstance")
public func __kk_kclass_isInstance(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return 0
    }
    return kk_op_is(valueRaw, box.typeToken)
}

/// Registers a single member (KFunction or KPropertyStub) for a KClass (STDLIB-REFLECT-ABI-002).
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

/// Returns the members of this KClass as a runtime list of KCallable handles.
/// When members have been registered via `__kk_kclass_register_member`, the list
/// contains the actual KFunction / KPropertyStub handles (STDLIB-REFLECT-ABI-002).
@_cdecl("__kk_kclass_members")
public func __kk_kclass_members(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.members(for: kclassRaw)))
}

/// Returns the constructors of this KClass as a runtime list of KFunction boxes.
/// Only constructors registered through `__kk_kconstructor_create` are returned.
@_cdecl("__kk_kclass_constructors")
public func __kk_kclass_constructors(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKConstructorRegistry.constructors(for: kclassRaw)))
}

/// Returns the nested classes of this KClass as a runtime list of KClass handles.
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

/// Registers the companion object's (typeToken, nameHint) pair for a class's
/// type token. Emitted during class reflection metadata setup (KUU-1357).
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

/// Returns the companion object's `KClass` for this KClass, or the null
/// sentinel when the class declares no companion (KUU-1357).
@_cdecl("__kk_kclass_companion_object")
public func __kk_kclass_companion_object(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let entry = runtimeKCompanionRegistry.companion(for: box.typeToken)
    else {
        return runtimeNullSentinelInt
    }
    return __kk_kclass_create(entry.token, entry.nameRaw)
}

/// Registers one nested class's (typeToken, nameHint) pair for a class's
/// type token. Emitted once per nested class during class reflection metadata
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

/// Returns the primary constructor of this KClass as a KConstructor box, or null sentinel if none.
/// STDLIB-REFLECT-064
@_cdecl("__kk_kclass_primary_constructor")
public func __kk_kclass_primary_constructor(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return runtimeNullSentinelInt
    }
    return runtimeKConstructorRegistry.primaryConstructor(for: kclassRaw) ?? runtimeNullSentinelInt
}

// MARK: - STDLIB-REFLECT-061: KClass member access (properties, functions, etc.)

/// Returns all properties (including inherited) of this KClass as a runtime list.
/// Returns registered `RuntimeKPropertyStub` handles only.
@_cdecl("__kk_kclass_properties")
public func __kk_kclass_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

/// Returns the non-extension member properties of this KClass as a runtime list.
/// These are the properties declared directly in the class or its superclasses,
/// excluding extension properties.
@_cdecl("__kk_kclass_member_properties")
public func __kk_kclass_member_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

/// Returns the declared member properties of this KClass (own class only, not inherited).
/// These are properties explicitly declared in this class, excluding superclass properties.
@_cdecl("__kk_kclass_declared_member_properties")
public func __kk_kclass_declared_member_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

/// Returns all functions (including inherited) of this KClass as a runtime list.
/// Returns registered `RuntimeKFunctionBox` handles only.
@_cdecl("__kk_kclass_functions")
public func __kk_kclass_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

/// Returns the non-extension member functions of this KClass as a runtime list.
/// These are functions declared in the class or its superclasses, excluding extensions.
@_cdecl("__kk_kclass_member_functions")
public func __kk_kclass_member_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

/// Returns the declared member functions of this KClass (own class only, not inherited).
/// These are functions explicitly declared in this class, excluding superclass functions.
@_cdecl("__kk_kclass_declared_member_functions")
public func __kk_kclass_declared_member_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

// MARK: - STDLIB-REFLECT-ABI-003: KClass.cast / KClass.safeCast

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

/// Tries to cast `valueRaw` to the type represented by this KClass.
/// Returns `valueRaw` if the value is an instance, or the null sentinel if not.
/// Never throws; equivalent to Kotlin's `safeCast` (`value as? T`).
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass.
///   - valueRaw: The value to cast.
/// - Returns: `valueRaw` on success, or `runtimeNullSentinelInt` if not an instance.
@_cdecl("__kk_kclass_safeCast")
public func __kk_kclass_safeCast(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    let isInstance = kk_op_is(valueRaw, box.typeToken)
    return isInstance != 0 ? valueRaw : runtimeNullSentinelInt
}
