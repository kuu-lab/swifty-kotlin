
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

private func runtimeThrowStringIndexOutOfBounds(
    _ outThrown: UnsafeMutablePointer<Int>?,
    message: String
) {
    guard let outThrown else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: StringIndexOutOfBoundsException: \(message)")
    }
    runtimeSetThrown(
        outThrown,
        runtimeAllocateThrowable(message: "StringIndexOutOfBoundsException: \(message)")
    )
}

// MARK: - @_cdecl functions

@_cdecl("kk_string_builder_new")
public func kk_string_builder_new() -> Int {
    registerRuntimeObject(RuntimeStringBuilderBox())
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

// ABI note: The old camelCase symbols (kk_string_builder_appendLine_obj) were never part of
// a shipped/stable ABI. This rename to snake_case happened before any release, so there are
// no pre-existing compiled artifacts that reference the old names.
@_cdecl("kk_string_builder_append_line_obj")
public func kk_string_builder_append_line_obj(_ sbRaw: Int, _ valueRaw: Int) -> Int {
    runtimeStringBuilderAppendLine(sbRaw, value: runtimeElementToString(valueRaw))
}

@_cdecl("kk_string_builder_append_line_obj_flat")
public func kk_string_builder_append_line_obj_flat(
    _ sbRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringBuilderAppendLine(
        sbRaw,
        value: runtimeStringBuilderObjectStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeStringBuilderAppendLine(_ sbRaw: Int, value: String) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append(value)
    sb.value.append("\n")
    return sbRaw
}

// ABI note: Same as above — old camelCase symbol never shipped; rename is safe.
@_cdecl("kk_string_builder_append_line_noarg_obj")
public func kk_string_builder_append_line_noarg_obj(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append("\n")
    return sbRaw
}

@_cdecl("kk_string_builder_insert_obj")
public func kk_string_builder_insert_obj(_ sbRaw: Int, _ index: Int, _ valueRaw: Int) -> Int {
    runtimeStringBuilderInsert(sbRaw, index: index, value: runtimeElementToString(valueRaw), outThrown: nil)
}

@_cdecl("kk_string_builder_insert_obj_flat")
public func kk_string_builder_insert_obj_flat(
    _ sbRaw: Int,
    _ index: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringBuilderInsert(
        sbRaw,
        index: index,
        value: runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash),
        outThrown: nil
    )
}

private func runtimeStringBuilderInsert(_ sbRaw: Int, index: Int, value str: String, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index <= utf8Count else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return sbRaw
    }
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    let insertionPoint = String.Index(utf8Index, within: sb.value) ?? sb.value.endIndex
    sb.value.insert(contentsOf: str, at: insertionPoint)
    return sbRaw
}

@_cdecl("kk_string_builder_delete_obj")
public func kk_string_builder_delete_obj(
    _ sbRaw: Int,
    _ start: Int,
    _ end: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let len = sb.value.utf8.count
    guard start >= 0, start <= len, end >= start, end <= len else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "start=\(start), end=\(end), length=\(len)")
        return sbRaw
    }
    let startIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: start)
    let endIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: end)
    let sIdx = String.Index(startIdx, within: sb.value) ?? sb.value.endIndex
    let eIdx = String.Index(endIdx, within: sb.value) ?? sb.value.endIndex
    sb.value.removeSubrange(sIdx..<eIdx)
    return sbRaw
}

@_cdecl("kk_string_builder_deleteRange")
public func kk_string_builder_deleteRange(
    _ sbRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_builder_delete_obj(sbRaw, startIndex, endIndex, outThrown)
}

@_cdecl("kk_string_builder_clear")
public func kk_string_builder_clear(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value = ""
    return sbRaw
}

@_cdecl("kk_string_builder_reverse")
public func kk_string_builder_reverse(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value = String(sb.value.reversed())
    return sbRaw
}

@_cdecl("kk_string_builder_deleteCharAt")
public func kk_string_builder_deleteCharAt(
    _ sbRaw: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index < utf8Count else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return sbRaw
    }
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    guard let charIdx = String.Index(utf8Index, within: sb.value) else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return sbRaw
    }
    sb.value.remove(at: charIdx)
    return sbRaw
}

@_cdecl("kk_string_builder_deleteAt")
public func kk_string_builder_deleteAt(
    _ sbRaw: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_builder_deleteCharAt(sbRaw, index, outThrown)
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

@_cdecl("kk_string_builder_insertRange_obj")
public func kk_string_builder_insertRange_obj(_ sbRaw: Int, _ index: Int, _ csqRaw: Int, _ startIndex: Int, _ endIndex: Int) -> Int {
    runtimeStringBuilderInsertRange(
        sbRaw,
        index: index,
        csq: runtimeElementToString(csqRaw),
        startIndex: startIndex,
        endIndex: endIndex,
        outThrown: nil
    )
}

@_cdecl("kk_string_builder_insertRange_obj_flat")
public func kk_string_builder_insertRange_obj_flat(
    _ sbRaw: Int,
    _ index: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ startIndex: Int,
    _ endIndex: Int
) -> Int {
    runtimeStringBuilderInsertRange(
        sbRaw,
        index: index,
        csq: runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash),
        startIndex: startIndex,
        endIndex: endIndex,
        outThrown: nil
    )
}

private func runtimeStringBuilderInsertRange(
    _ sbRaw: Int,
    index: Int,
    csq: String,
    startIndex: Int,
    endIndex: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index <= utf8Count else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return sbRaw
    }
    let slice = runtimeUTF16Substring(csq, startIndex: startIndex, endIndex: endIndex)
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    let insertionPoint = String.Index(utf8Index, within: sb.value) ?? sb.value.endIndex
    sb.value.insert(contentsOf: slice, at: insertionPoint)
    return sbRaw
}

@_cdecl("kk_string_builder_setRange")
public func kk_string_builder_setRange(_ sbRaw: Int, _ startIndex: Int, _ endIndex: Int, _ valueRaw: Int) -> Int {
    runtimeStringBuilderSetRange(
        sbRaw,
        startIndex: startIndex,
        endIndex: endIndex,
        value: runtimeElementToString(valueRaw),
        outThrown: nil
    )
}

@_cdecl("kk_string_builder_setRange_flat")
public func kk_string_builder_setRange_flat(
    _ sbRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringBuilderSetRange(
        sbRaw,
        startIndex: startIndex,
        endIndex: endIndex,
        value: runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash),
        outThrown: nil
    )
}

private func runtimeStringBuilderSetRange(
    _ sbRaw: Int,
    startIndex: Int,
    endIndex: Int,
    value: String,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let len = sb.value.utf8.count
    guard startIndex >= 0, startIndex <= len, endIndex >= startIndex, endIndex <= len else {
        runtimeThrowStringIndexOutOfBounds(
            outThrown,
            message: "startIndex=\(startIndex), endIndex=\(endIndex), length=\(len)"
        )
        return sbRaw
    }
    let startIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: startIndex)
    let endIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: endIndex)
    let sIdx = String.Index(startIdx, within: sb.value) ?? sb.value.endIndex
    let eIdx = String.Index(endIdx, within: sb.value) ?? sb.value.endIndex
    sb.value.replaceSubrange(sIdx..<eIdx, with: value)
    return sbRaw
}

// MARK: - STDLIB-STR-123: Additional StringBuilder methods

@_cdecl("kk_string_builder_replace_obj_flat")
public func kk_string_builder_replace_obj_flat(
    _ sbRaw: Int,
    _ start: Int,
    _ end: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringBuilderReplace(
        sbRaw,
        start: start,
        end: end,
        replacement: runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeStringBuilderReplace(
    _ sbRaw: Int,
    start: Int,
    end: Int,
    replacement: String
) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let len = sb.value.utf8.count
    let clampedEnd = min(end, len)
    guard start >= 0, start <= len, clampedEnd >= start else {
        fatalError("StringIndexOutOfBoundsException: start=\(start), end=\(end), length=\(len)")
    }
    let startIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: start)
    let endIdx = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: clampedEnd)
    let sIdx = String.Index(startIdx, within: sb.value) ?? sb.value.endIndex
    let eIdx = String.Index(endIdx, within: sb.value) ?? sb.value.endIndex
    sb.value.replaceSubrange(sIdx..<eIdx, with: replacement)
    return sbRaw
}

@_cdecl("kk_string_builder_setCharAt")
public func kk_string_builder_setCharAt(
    _ sbRaw: Int,
    _ index: Int,
    _ charValue: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index < utf8Count else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return sbRaw
    }
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    guard let charIdx = String.Index(utf8Index, within: sb.value) else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return sbRaw
    }
    // charValue is a boxed Char (unicode scalar value)
    let unboxed = kk_unbox_char(charValue)
    guard let scalar = Unicode.Scalar(unboxed) else { return sbRaw }
    sb.value.replaceSubrange(charIdx...charIdx, with: String(scalar))
    return sbRaw
}

@_cdecl("kk_string_builder_capacity")
public func kk_string_builder_capacity(_ sbRaw: Int) -> Int {
    // Swift Strings have no separate capacity concept; return length + 16 as a
    // reasonable default (mirrors the JVM default initial capacity of 16).
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 16 }
    return sb.value.utf8.count + 16
}

@_cdecl("kk_string_builder_ensureCapacity")
public func kk_string_builder_ensureCapacity(_ sbRaw: Int, _ minimumCapacity: Int) -> Int {
    // Swift Strings handle memory automatically; this is a no-op at runtime.
    return sbRaw
}

@_cdecl("kk_string_builder_trimToSize")
public func kk_string_builder_trimToSize(_ sbRaw: Int) -> Int {
    // Swift Strings handle memory automatically; this is a no-op at runtime.
    return sbRaw
}

@_cdecl("kk_string_builder_get")
public func kk_string_builder_get(
    _ sbRaw: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    let utf8Count = sb.value.utf8.count
    guard index >= 0, index < utf8Count else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return 0
    }
    let utf8Index = sb.value.utf8.index(sb.value.utf8.startIndex, offsetBy: index)
    guard let charIdx = String.Index(utf8Index, within: sb.value) else {
        runtimeThrowStringIndexOutOfBounds(outThrown, message: "index=\(index), length=\(utf8Count)")
        return 0
    }
    let charValue = Int(sb.value[charIdx].unicodeScalars.first?.value ?? 0)
    return kk_box_char(charValue)
}

// MARK: - STDLIB-TEXT-FN-003: Typed append overloads

/// append(value: Boolean): StringBuilder
/// Accepts the raw unboxed boolean (0 or 1) and appends "false" or "true".
@_cdecl("kk_string_builder_append_bool")
public func kk_string_builder_append_bool(_ sbRaw: Int, _ value: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.value.append(value != 0 ? "true" : "false")
    return sbRaw
}

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

/// append(value: Float): StringBuilder
/// Accepts the raw float bits (via kk_bits_to_float) or a boxed RuntimeFloatBox.
@_cdecl("kk_string_builder_append_float")
public func kk_string_builder_append_float(_ sbRaw: Int, _ value: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer, let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
            sb.value.append(runtimeFormatFloatingPoint(floatBox.value))
            return sbRaw
        }
    }
    sb.value.append(runtimeFormatFloatingPoint(kk_bits_to_float(value)))
    return sbRaw
}

/// append(value: Double): StringBuilder
/// Accepts the raw double bits (via kk_bits_to_double) or a boxed RuntimeDoubleBox.
@_cdecl("kk_string_builder_append_double")
public func kk_string_builder_append_double(_ sbRaw: Int, _ value: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer, let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
            sb.value.append(runtimeFormatFloatingPoint(doubleBox.value))
            return sbRaw
        }
    }
    sb.value.append(runtimeFormatFloatingPoint(kk_bits_to_double(value)))
    return sbRaw
}

// MARK: - STDLIB-TEXT-EDGE-012: append(vararg) overloads

/// Append each element in an array/list of values to the StringBuilder.
/// Corresponds to StringBuilder.append(vararg value: String?) and
/// StringBuilder.append(vararg value: Any?).
///
/// Some lowering paths still pass a single boxed/raw element instead of a packed
/// list for singleton varargs, so we accept that form here as a one-element vararg.
@_cdecl("kk_string_builder_append_vararg_obj")
public func kk_string_builder_append_vararg_obj(_ sbRaw: Int, _ argsArrayRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    let elements = runtimeArrayBox(from: argsArrayRaw)?.elements
        ?? runtimeListBox(from: argsArrayRaw)?.elements
        ?? [argsArrayRaw]
    for element in elements {
        sb.value.append(runtimeElementToString(element))
    }
    return sbRaw
}
