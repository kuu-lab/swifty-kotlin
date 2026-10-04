
// MARK: - StringBuilder Runtime Type (STDLIB-255/256/257)

final class RuntimeStringBuilderBox {
    /// Contents as Kotlin UTF-16 code units. Positional runtime operations
    /// (length/get/indexOf/insert/substring/...) work on this buffer directly;
    /// a Swift `String` is materialized only when a result needs one.
    var units: [UInt16]

    init(_ initial: String = "") {
        self.units = runtimeKotlinStringUTF16CodeUnits(initial)
    }

    init(units: [UInt16]) {
        self.units = units
    }

    var stringValue: String {
        runtimeKotlinStringFromUTF16CodeUnits(units)
    }
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
    runtimeRegisterCharSequenceItable(raw)
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

@_cdecl("__kk_string_builder_new_from_char_sequence")
public func __kk_string_builder_new_from_char_sequence(_ valueRaw: Int) -> Int {
    if let units = runtimeCharSequenceUTF16Units(from: valueRaw) {
        return runtimeStringBuilderNew(units: units)
    }
    return runtimeStringBuilderNew(initial: runtimeElementToString(valueRaw))
}

// BUG-165: StringBuilder(capacity: Int) has no Kotlin-level body (see
// StringBuilder.kt) — construction is entirely native. The capacity is only
// ever used as a preallocation hint (this runtime doesn't preallocate string
// storage), but real Kotlin/Java still rejects a negative capacity with
// NegativeArraySizeException, so this must validate rather than silently
// ignore it the way falling through to __kk_string_builder_new did before.
@_cdecl("__kk_string_builder_new_capacity_checked")
public func __kk_string_builder_new_capacity_checked(
    _ capacity: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard capacity >= 0 else {
        runtimeSetThrown(outThrown, runtimeAllocateNegativeArraySizeException(message: "\(capacity)"))
        return 0
    }
    return runtimeStringBuilderNew(initial: "")
}

private func runtimeStringBuilderNew(initial: String) -> Int {
    runtimeRegisterStringBuilderType(registerRuntimeObject(RuntimeStringBuilderBox(initial)))
}

private func runtimeStringBuilderNew(units: [UInt16]) -> Int {
    runtimeRegisterStringBuilderType(registerRuntimeObject(RuntimeStringBuilderBox(units: units)))
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

private func stringBuilderCharArrayUnits(
    from raw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [UInt16]? {
    guard let array = runtimeArrayBox(from: raw) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "expected CharArray handle")
        )
        return nil
    }
    return array.elements.map { UInt16(truncatingIfNeeded: kk_unbox_char($0)) }
}

private func stringBuilderIndexError(
    outThrown: UnsafeMutablePointer<Int>?,
    message: String
) {
    runtimeSetThrown(outThrown, runtimeAllocateIndexOutOfBoundsException(message: message))
}

private func stringBuilderIndexOf(_ source: [UInt16], _ needle: [UInt16], from startIndex: Int) -> Int {
    let start = max(0, startIndex)
    if needle.isEmpty {
        return min(start, source.count)
    }
    guard start <= source.count - needle.count else {
        return -1
    }
    for index in start ... (source.count - needle.count)
        where source[index ..< index + needle.count].elementsEqual(needle)
    {
        return index
    }
    return -1
}

private func stringBuilderLastIndexOf(_ source: [UInt16], _ needle: [UInt16], from startIndex: Int) -> Int {
    guard startIndex >= 0 else {
        return -1
    }
    if needle.isEmpty {
        return min(startIndex, source.count)
    }
    let lastStart = source.count - needle.count
    guard lastStart >= 0 else {
        return -1
    }
    var index = min(startIndex, lastStart)
    while index >= 0 {
        if source[index ..< index + needle.count].elementsEqual(needle) {
            return index
        }
        index -= 1
    }
    return -1
}

@_cdecl("__kk_string_builder_append_obj")
public func __kk_string_builder_append_obj(_ sbRaw: Int, _ valueRaw: Int) -> Int {
    runtimeStringBuilderAppend(sbRaw, value: runtimeElementToString(valueRaw))
}

// Retain the direct append bridge for existing runtime ABI callers. Kotlin
// Appendable calls dispatch through source-backed implementations and itables.
@_cdecl("__kk_string_builder_append_char")
public func __kk_string_builder_append_char(_ sbRaw: Int, _ charRaw: Int) -> Int {
    runtimeStringBuilderAppend(sbRaw, value: runtimeCharacterFromRaw(charRaw))
}

@_cdecl("__kk_string_builder_append_char_array")
public func __kk_string_builder_append_char_array(
    _ sbRaw: Int,
    _ arrayRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    guard let arrayUnits = stringBuilderCharArrayUnits(from: arrayRaw, outThrown: outThrown) else {
        return sbRaw
    }
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= arrayUnits.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "startIndex=\(startIndex), endIndex=\(endIndex), size=\(arrayUnits.count)"
        )
        return sbRaw
    }
    sb.units.append(contentsOf: arrayUnits[startIndex ..< endIndex])
    return sbRaw
}

@_cdecl("__kk_string_builder_insert_obj")
public func __kk_string_builder_insert_obj(
    _ sbRaw: Int,
    _ index: Int,
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    guard index >= 0, index <= sb.units.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "index=\(index), length=\(sb.units.count)"
        )
        return sbRaw
    }
    let inserted = runtimeStringOrBuilderUTF16Units(from: valueRaw)
        ?? runtimeKotlinStringUTF16CodeUnits(runtimeElementToString(valueRaw))
    sb.units.insert(contentsOf: inserted, at: index)
    return sbRaw
}

@_cdecl("__kk_string_builder_insert_char_sequence")
public func __kk_string_builder_insert_char_sequence(
    _ sbRaw: Int,
    _ index: Int,
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    guard index >= 0, index <= sb.units.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "index=\(index), length=\(sb.units.count)"
        )
        return sbRaw
    }

    guard let sourceBuilder = runtimeStringBuilderBox(from: valueRaw) else {
        let inserted = runtimeStringOrBuilderUTF16Units(from: valueRaw)
            ?? runtimeKotlinStringUTF16CodeUnits(runtimeElementToString(valueRaw))
        sb.units.insert(contentsOf: inserted, at: index)
        return sbRaw
    }

    let sourceLength = sourceBuilder.units.count
    if sourceBuilder === sb {
        // Java shifts the destination tail before reading a self-referential
        // CharSequence. Keep that overlap behavior by reading the working buffer
        // after the shift while filling the inserted window.
        let originalLength = sb.units.count
        sb.units.append(contentsOf: repeatElement(0, count: sourceLength))
        if index < originalLength {
            for sourceIndex in stride(from: originalLength - 1, through: index, by: -1) {
                sb.units[sourceIndex + sourceLength] = sb.units[sourceIndex]
            }
        }
        for offset in 0 ..< sourceLength {
            sb.units[index + offset] = sb.units[offset]
        }
    } else {
        sb.units.insert(contentsOf: sourceBuilder.units, at: index)
    }
    return sbRaw
}

@_cdecl("__kk_string_builder_insert_char_array")
public func __kk_string_builder_insert_char_array(
    _ sbRaw: Int,
    _ index: Int,
    _ arrayRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    guard let arrayUnits = stringBuilderCharArrayUnits(from: arrayRaw, outThrown: outThrown) else {
        return sbRaw
    }
    guard index >= 0, index <= sb.units.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "index=\(index), length=\(sb.units.count)"
        )
        return sbRaw
    }
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= arrayUnits.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "startIndex=\(startIndex), endIndex=\(endIndex), size=\(arrayUnits.count)"
        )
        return sbRaw
    }
    sb.units.insert(contentsOf: arrayUnits[startIndex ..< endIndex], at: index)
    return sbRaw
}

@_cdecl("__kk_string_builder_index_of")
public func __kk_string_builder_index_of(_ sbRaw: Int, _ stringRaw: Int, _ startIndex: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return -1 }
    let needle = runtimeStringUTF16CodeUnits(stringRaw)
    return stringBuilderIndexOf(sb.units, needle, from: startIndex)
}

@_cdecl("__kk_string_builder_last_index_of")
public func __kk_string_builder_last_index_of(_ sbRaw: Int, _ stringRaw: Int, _ startIndex: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return -1 }
    let needle = runtimeStringUTF16CodeUnits(stringRaw)
    return stringBuilderLastIndexOf(sb.units, needle, from: startIndex)
}

@_cdecl("__kk_string_builder_set_length")
public func __kk_string_builder_set_length(
    _ sbRaw: Int,
    _ newLength: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    guard newLength >= 0 else {
        stringBuilderIndexError(outThrown: outThrown, message: "newLength=\(newLength)")
        return sbRaw
    }
    if newLength < sb.units.count {
        sb.units.removeLast(sb.units.count - newLength)
    } else if newLength > sb.units.count {
        sb.units.append(contentsOf: repeatElement(0, count: newLength - sb.units.count))
    }
    return sbRaw
}

@_cdecl("__kk_string_builder_substring")
public func __kk_string_builder_substring(
    _ sbRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return runtimeMakeStringRaw("") }
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= sb.units.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "startIndex=\(startIndex), endIndex=\(endIndex), length=\(sb.units.count)"
        )
        return 0
    }
    return runtimeMakeStringRaw(
        runtimeKotlinStringFromUTF16CodeUnits(Array(sb.units[startIndex ..< endIndex]))
    )
}

@_cdecl("__kk_string_builder_to_char_array")
public func __kk_string_builder_to_char_array(
    _ sbRaw: Int,
    _ destinationRaw: Int,
    _ destinationOffset: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    guard let destination = runtimeArrayBox(from: destinationRaw) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "expected CharArray handle")
        )
        return 0
    }
    let source = sb.units
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= source.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "startIndex=\(startIndex), endIndex=\(endIndex), length=\(source.count)"
        )
        return 0
    }
    let copyCount = endIndex - startIndex
    let (destinationEnd, overflow) = destinationOffset.addingReportingOverflow(copyCount)
    guard destinationOffset >= 0, !overflow, destinationEnd <= destination.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "destinationOffset=\(destinationOffset), length=\(copyCount), size=\(destination.count)"
        )
        return 0
    }
    for offset in 0 ..< copyCount {
        destination[destinationOffset + offset] = kk_box_char(Int(source[startIndex + offset]))
    }
    return 0
}

@_cdecl("__kk_string_builder_length_utf16")
public func __kk_string_builder_length_utf16(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    return sb.units.count
}

@_cdecl("__kk_string_builder_append_range")
public func __kk_string_builder_append_range(
    _ sbRaw: Int,
    _ valueRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let stringRaw = valueRaw == runtimeNullSentinelInt ? runtimeMakeStringRaw("null") : valueRaw
    guard let source = runtimeStringFromRaw(stringRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_string_builder_append_range received invalid string handle")
    }
    let utf16 = runtimeStringUTF16CodeUnits(stringRaw)
    let length = utf16.count
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= length else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "startIndex=\(startIndex), endIndex=\(endIndex), size=\(length)"
        )
        return sbRaw
    }
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.units.append(contentsOf: utf16[startIndex ..< endIndex])
    return sbRaw
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
    runtimeAppendKotlinUTF16CodeUnits(of: value, to: &sb.units)
    return sbRaw
}

@_cdecl("__kk_string_builder_toString")
public func __kk_string_builder_toString(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else {
        return sbMakeStringRaw("")
    }
    return sbMakeStringRaw(sb.stringValue)
}

@_cdecl("__kk_string_builder_get")
public func __kk_string_builder_get(
    _ sbRaw: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    guard index >= 0, index < sb.units.count else {
        stringBuilderIndexError(
            outThrown: outThrown,
            message: "index=\(index), length=\(sb.units.count)"
        )
        return 0
    }
    return Int(sb.units[index])
}

@_cdecl("__kk_string_builder_length_prop")
public func __kk_string_builder_length_prop(_ sbRaw: Int) -> Int {
    // KSP-817: StringBuilder.length must agree with String.length and with
    // CharSequence.length dispatch, all of which count UTF-16 code units.
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return 0 }
    return sb.units.count
}

@_cdecl("__kk_string_builder_clear")
public func __kk_string_builder_clear(_ sbRaw: Int) -> Int {
    guard let sb = runtimeStringBuilderBox(from: sbRaw) else { return sbRaw }
    sb.units.removeAll()
    return sbRaw
}
