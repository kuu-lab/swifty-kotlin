
// MARK: - StringBuilder Runtime Type (STDLIB-255/256/257)

final class RuntimeStringBuilderBox {
    var value: String
    init(_ initial: String = "") { self.value = initial }
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

@_cdecl("kk_string_builder_new")
public func kk_string_builder_new() -> Int {
    registerRuntimeObject(RuntimeStringBuilderBox())
}

@_cdecl("kk_string_builder_new_with_capacity")
public func kk_string_builder_new_with_capacity(_ capacity: Int) -> Int {
    // capacity is an allocation hint only (mirrors kk_string_builder_ensureCapacity);
    // Swift String manages its own storage, so there is no separate capacity to apply.
    registerRuntimeObject(RuntimeStringBuilderBox())
}

@_cdecl("kk_string_builder_new_from_string")
public func kk_string_builder_new_from_string(_ strRaw: Int) -> Int {
    runtimeStringBuilderNew(initial: runtimeStringFromRawOrPanic(strRaw, caller: #function))
}

@_cdecl("kk_string_builder_new_from_string_flat")
public func kk_string_builder_new_from_string_flat(
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
    registerRuntimeObject(RuntimeStringBuilderBox(initial))
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

@_cdecl("kk_string_builder_append_obj")
public func kk_string_builder_append_obj(_ sbRaw: Int, _ valueRaw: Int) -> Int {
    runtimeStringBuilderAppend(sbRaw, value: runtimeElementToString(valueRaw))
}

@_cdecl("kk_string_builder_append_obj_flat")
public func kk_string_builder_append_obj_flat(
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

@_cdecl("kk_string_builder_toString")
public func kk_string_builder_toString(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else {
        return sbMakeStringRaw("")
    }
    return sbMakeStringRaw(sb.value)
}

@_cdecl("kk_string_builder_length_prop")
public func kk_string_builder_length_prop(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    return sb.value.utf8.count
}

@_cdecl("kk_string_builder_clear")
public func kk_string_builder_clear(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value = ""
    return sbRaw
}

@_cdecl("kk_string_builder_appendRange_obj_flat")
public func kk_string_builder_appendRange_obj_flat(
    _ sbRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ startIndex: Int,
    _ endIndex: Int
) -> Int {
    runtimeStringBuilderAppendRange(
        sbRaw,
        csq: runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash),
        startIndex: startIndex,
        endIndex: endIndex
    )
}

private func runtimeStringBuilderAppendRange(
    _ sbRaw: Int,
    csq: String,
    startIndex: Int,
    endIndex: Int
) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    // Use UTF-16 code unit indexing to match Kotlin CharSequence semantics.
    sb.value.append(runtimeUTF16Substring(csq, startIndex: startIndex, endIndex: endIndex))
    return sbRaw
}

// MARK: - Appendable compatibility bridge

/// append(value: Char): StringBuilder
/// Accepts the raw unboxed char (unicode scalar value or boxed CharBox) and appends the character.
@_cdecl("kk_string_builder_append_char")
public func kk_string_builder_append_char(_ sbRaw: Int, _ value: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    // The value may be either a boxed RuntimeCharBox or a raw unicode scalar.
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer, let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
            let rendered = UnicodeScalar(charBox.value).map(String.init) ?? "?"
            sb.value.append(rendered)
            return sbRaw
        }
    }
    let rendered = UnicodeScalar(value).map(String.init) ?? "?"
    sb.value.append(rendered)
    return sbRaw
}
