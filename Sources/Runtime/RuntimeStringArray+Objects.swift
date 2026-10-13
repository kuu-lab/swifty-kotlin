import Foundation
import RuntimeABI

@_cdecl("kk_object_new")
public func kk_object_new(_ length: Int, _ classId: Int) -> Int {
    let box = RuntimeObjectBox(length: length, classID: Int64(classId))
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    let key = UInt(bitPattern: opaque)
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(key)
    }
    runtimeStorage.withMetadataLock { state in
        state.objectTypeByPointer[key] = Int64(classId)
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_object_type_id")
public func kk_object_type_id(_ objectRaw: Int) -> Int {
    Int(runtimeObjectTypeID(rawValue: objectRaw) ?? 0)
}

@_cdecl("kk_type_register_super")
public func kk_type_register_super(_ childTypeId: Int, _ superTypeId: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: Int64(childTypeId), parentTypeID: Int64(superTypeId))
    return 0
}

@_cdecl("kk_type_register_iface")
public func kk_type_register_iface(_ childTypeId: Int, _ ifaceTypeId: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: Int64(childTypeId), parentTypeID: Int64(ifaceTypeId))
    return 0
}

@_cdecl("kk_object_register_itable_iface")
public func kk_object_register_itable_iface(
    _ objectRaw: Int,
    _ ifaceTypeId: Int,
    _ ifaceSlot: Int
) -> Int {
    guard ifaceTypeId != 0,
          ifaceSlot >= 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    runtimeStorage.withMetadataLock { state in
        var slots = state.objectInterfaceSlots[objectKey] ?? [:]
        slots[Int64(ifaceTypeId)] = ifaceSlot
        state.objectInterfaceSlots[objectKey] = slots
    }
    return 0
}

@_cdecl("kk_object_register_itable_method")
public func kk_object_register_itable_method(
    _ objectRaw: Int,
    _ ifaceSlot: Int,
    _ methodSlot: Int,
    _ functionRaw: Int
) -> Int {
    guard ifaceSlot >= 0,
          methodSlot >= 0,
          functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    let dispatchKey = (UInt64(UInt32(ifaceSlot)) << 32) | UInt64(UInt32(methodSlot))
    runtimeStorage.withMetadataLock { state in
        var methods = state.objectItableMethods[objectKey] ?? [:]
        methods[dispatchKey] = functionRaw
        state.objectItableMethods[objectKey] = methods
    }
    return 0
}

@_cdecl("kk_object_register_vtable_method")
public func kk_object_register_vtable_method(
    _ objectRaw: Int,
    _ methodSlot: Int,
    _ functionRaw: Int
) -> Int {
    guard methodSlot >= 0,
          functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    runtimeStorage.withMetadataLock { state in
        var methods = state.objectVtableMethods[objectKey] ?? [:]
        methods[methodSlot] = functionRaw
        state.objectVtableMethods[objectKey] = methods
    }
    return 0
}

/// Registers the most-specific user implementation of `Any.equals` for an
/// object whose equality may later be evaluated through an erased type.
@_cdecl("kk_object_register_equals_override")
public func kk_object_register_equals_override(_ objectRaw: Int, _ functionRaw: Int) -> Int {
    guard functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    runtimeStorage.withMetadataLock { state in
        state.objectEqualsOverrides[objectKey] = functionRaw
    }
    return 0
}

/// Registers the most-specific user implementation of `Any.hashCode` so that
/// hashed collections, which only see an erased handle, honor it.
@_cdecl("kk_object_register_hashcode_override")
public func kk_object_register_hashcode_override(_ objectRaw: Int, _ functionRaw: Int) -> Int {
    guard functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    runtimeStorage.withMetadataLock { state in
        state.objectHashCodeOverrides[objectKey] = functionRaw
    }
    return 0
}

@_cdecl("kk_object_register_any_to_string")
public func kk_object_register_any_to_string(
    _ objectRaw: Int,
    _ functionRaw: Int
) -> Int {
    guard functionRaw != 0,
          let objectPtr = UnsafeMutableRawPointer(bitPattern: objectRaw)
    else {
        return 0
    }
    let objectKey = UInt(bitPattern: objectPtr)
    runtimeStorage.withMetadataLock { state in
        state.objectAnyToStringMethods[objectKey] = functionRaw
    }
    return 0
}

/// Registers the Any-erased toString bridge for a value class. Value classes
/// are represented by boxed underlying primitives at reference boundaries, so
/// the nominal class ID is the stable dispatch key rather than an object
/// pointer.
@_cdecl("kk_value_class_register_any_to_string")
public func kk_value_class_register_any_to_string(
    _ classID: Int,
    _ functionRaw: Int
) -> Int {
    guard classID != 0, functionRaw != 0 else {
        return 0
    }
    runtimeStorage.withMetadataLock { state in
        state.valueClassAnyToStringMethods[Int64(classID)] = functionRaw
    }
    return 0
}
