// String higher-order functions and commonPrefix/Suffix helpers.
// Split out from `RuntimeStringStdlib.swift`.
// KSP-410: filter/filterNot/map/mapIndexed/mapNotNull/any/all/none/count/
// find/findLast/firstNotNullOf/firstNotNullOfOrNull/onEach/onEachIndexed/
// partition/sumBy/sumByDouble/filterIndexed and the whole reduce/fold family
// moved to bundled Kotlin source (Stdlib/kotlin/text/StringHOF.kt) — all
// avoid named labels in their function-type parameters (workaround for
// BUG-169, see TODO.md).

import Foundation

private func runtimeStringHOFElementValue(_ raw: Int) -> RuntimeValue {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return RuntimeValue(raw: maybeUnbox(raw))
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return RuntimeValue(raw: maybeUnbox(raw))
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return RuntimeValue(charScalar: charBox.value)
    }
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        return runtimeStringHOFStringValue(stringBox.value)
    }
    return RuntimeValue(raw: maybeUnbox(raw))
}

private func runtimeStringHOFStringValue(_ value: String) -> RuntimeValue {
    var length = 0
    var byteCount = 0
    var hash = 0
    let data = runtimeRegisterFlatString(
        value,
        outLength: &length,
        outByteCount: &byteCount,
        outHash: &hash
    )
    guard let data else {
        return RuntimeValue(raw: 0)
    }
    return RuntimeValue(
        stringData: Int(bitPattern: data),
        length: length,
        byteCount: byteCount,
        hash: hash
    )
}

// MARK: - STDLIB-192: equals(other)
// KSP-413: equals(other, ignoreCase) is bundled Kotlin source
// (Stdlib/kotlin/text/StringComparison.kt).

@_cdecl("kk_string_equals")
public func kk_string_equals(_ strRaw: Int, _ otherRaw: Int) -> Int {
    if otherRaw == runtimeNullSentinelInt {
        return kk_box_bool(0)
    }
    return kk_box_bool(kk_string_compareTo_member(strRaw, otherRaw) == 0 ? 1 : 0)
}

@_cdecl("kk_string_equals_flat")
public func kk_string_equals_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int
) -> Int {
    if data == nil || otherData == nil {
        return (data == nil && otherData == nil) ? 1 : 0
    }
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let other = runtimeStringFromFlatFields(data: otherData, length: otherLength, byteCount: otherByteCount, hash: otherHash)
    return source == other ? 1 : 0
}

// KSP-405: takeWhile/takeLastWhile/dropWhile are bundled Kotlin source
// (StringTakeDrop.kt); their runtime bridges were removed.

@_cdecl("kk_string_splitToSequence")
public func kk_string_splitToSequence(_ strRaw: Int, _ delimRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimRaw, caller: #function)

    if delimiter.isEmpty {
        let singleElement = runtimeMakeStringRaw(source)
        let seq = RuntimeSequenceBox(steps: [.source(elements: [singleElement])])
        return registerRuntimeObject(seq)
    }

    let splitStrings = runtimeSplitString(source, delimiter: delimiter).map { runtimeMakeStringRaw($0) }
    let seq = RuntimeSequenceBox(steps: [.source(elements: splitStrings)])
    return registerRuntimeObject(seq)
}

@_cdecl("__kk_string_splitToSequence")
public func __kk_string_splitToSequence(_ strRaw: Int, _ delimRaw: Int) -> Int {
    kk_string_splitToSequence(strRaw, delimRaw)
}

@_cdecl("kk_string_splitToSequence_flat")
public func kk_string_splitToSequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ delimData: UnsafePointer<UInt8>?,
    _ delimLength: Int,
    _ delimByteCount: Int,
    _ delimHash: Int
) -> Int {
    kk_string_splitToSequence(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimData, delimLength, delimByteCount, delimHash)
    )
}
