
// MARK: - StringBuilder Runtime Type (STDLIB-255/256/257)

final class RuntimeStringBuilderBox {
    var value: String
    init(_ initial: String = "") { self.value = initial }
}

// BUG-044: StringBuilder instances bypass normal kk_object_new-based class
// construction (see CallLowerer.lowerStringBuilderConstructorCall), so they
// never go through the compiler-emitted kk_type_register_super/
// kk_object_register_itable_iface calls a regular class gets. Without an
// object type ID and supertype edges, `sb is CharSequence`/`sb is Appendable`
// fell through kk_op_is's nominalBase case to the RuntimeThrowableBox
// fallback and incorrectly returned false. Register both explicitly here.
private let stringBuilderTypeID = runtimeStableNominalTypeID(fqName: "kotlin.text.StringBuilder")
private let stringBuilderCharSequenceSuperTypeID = runtimeStableNominalTypeID(fqName: "kotlin.CharSequence")
private let stringBuilderAppendableSuperTypeID = runtimeStableNominalTypeID(fqName: "kotlin.text.Appendable")

func runtimeRegisterStringBuilderType(_ raw: Int) -> Int {
    runtimeRegisterObjectType(rawValue: raw, classID: stringBuilderTypeID)
    runtimeRegisterTypeEdge(childTypeID: stringBuilderTypeID, parentTypeID: stringBuilderCharSequenceSuperTypeID)
    runtimeRegisterTypeEdge(childTypeID: stringBuilderTypeID, parentTypeID: stringBuilderAppendableSuperTypeID)
    return raw
}

private func runtimeStringBuilderBox(from raw: Int) -> RuntimeStringBuilderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    let isObject = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObject else { return nil }
    let unmanaged = Unmanaged<AnyObject>.fromOpaque(ptr)
    let obj = unmanaged.takeUnretainedValue()
    return obj as? RuntimeStringBuilderBox
}

private func sbMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - @_cdecl functions

@_cdecl("__kk_string_builder_new")
public func __kk_string_builder_new() -> Int {
    runtimeStringBuilderNew(initial: "")
}

@_cdecl("__kk_string_builder_new_from_string_flat")
public func __kk_string_builder_new_from_string_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringBuilderNew(
        initial: runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeStringBuilderNew(initial: String) -> Int {
    runtimeRegisterStringBuilderType(registerRuntimeObject(RuntimeStringBuilderBox(initial)))
}

private func runtimeStringBuilderObjectStringFromFlat(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> String {
    guard data != nil else {
        return "null"
    }
    return runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
}

@_cdecl("__kk_string_builder_append_obj")
public func __kk_string_builder_append_obj(_ sbRaw: Int, _ valueRaw: Int) -> Int {
    runtimeStringBuilderAppend(sbRaw, value: runtimeElementToString(valueRaw))
}

@_cdecl("__kk_string_builder_append_obj_flat")
public func __kk_string_builder_append_obj_flat(
    _ sbRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringBuilderAppend(
        sbRaw,
        value: runtimeStringBuilderObjectStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeStringBuilderAppend(_ sbRaw: Int, value: String) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append(value)
    return sbRaw
}

@_cdecl("__kk_string_builder_toString")
public func __kk_string_builder_toString(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else {
        return sbMakeStringRaw("")
    }
    return sbMakeStringRaw(sb.value)
}

@_cdecl("__kk_string_builder_length_prop")
public func __kk_string_builder_length_prop(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    return sb.value.utf8.count
}

@_cdecl("__kk_string_builder_clear")
public func __kk_string_builder_clear(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value = ""
    return sbRaw
}
