// String query and predicate functions (first/last/single,
// flat ifBlank/ifEmpty wrappers, get, compareTo, contentEquals, lines).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

// CharSequence.get occupies method slot 0, CharSequence.subSequence occupies
// method slot 1, and CharSequence.length occupies property getter slot 2.
// Runtime-created String boxes need all three entries so interface-typed calls
// use the same dispatch contract as source-defined CharSequence implementations.
private let runtimeCharSequenceInterfaceTypeID: Int64 =
    runtimeStableNominalTypeID(fqName: "kotlin.CharSequence")
private let runtimeCharSequenceGetMethod: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, index, outThrown in
    kk_char_sequence_get(raw, index, outThrown)
}
private let runtimeCharSequenceLengthGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_char_sequence_length(raw)
}
private let runtimeCharSequenceSubSequenceMethod: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, startIndex, endIndex, outThrown in
    kk_char_sequence_subSequence(raw, startIndex, endIndex, outThrown)
}

func runtimeRegisterCharSequenceItable(_ raw: Int) {
    _ = kk_object_register_itable_iface(
        raw,
        Int(runtimeCharSequenceInterfaceTypeID),
        0
    )
    _ = kk_object_register_itable_method(
        raw,
        0,
        0,
        unsafeBitCast(runtimeCharSequenceGetMethod, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw,
        0,
        1,
        unsafeBitCast(runtimeCharSequenceSubSequenceMethod, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw,
        0,
        2,
        unsafeBitCast(runtimeCharSequenceLengthGetter, to: Int.self)
    )
}

@_cdecl("kk_char_sequence_length")
public func kk_char_sequence_length(_ raw: Int) -> Int {
    // KSP-817: Match Kotlin's UTF-16 CharSequence.length contract. The receiver
    // may be any CharSequence implementation (String or StringBuilder handles).
    if let length = runtimeCharSequenceUTF16Length(from: raw) {
        return length
    }
    return runtimeKotlinStringUTF16Length(runtimeStringFromRawOrPanic(raw, caller: #function))
}

// KSP-1374/1384/1399: CharSequence first/last/single (+ OrNull) are
// source-backed via the __kk_string_*_flat bridges in RuntimeStringFlat.swift.
// The boxed (non-flat, Int-handle) kk_string_first/last/single/firstOrNull/
// lastOrNull/singleOrNull functions that used to live here were superseded
// and unreachable from any CompilerCore call site; removed.

@_cdecl("kk_string_getOrNull")
public func kk_string_getOrNull(_ strRaw: Int, _ index: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard index >= 0, index < codeUnits.count else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(codeUnits[index]))
}

/* KSP-1362: kk_string_ifBlank_flat / kk_string_ifEmpty_flat removed;
   ifBlank/ifEmpty are now bundled Kotlin source (StringEmptyBlankLines.kt)
   on generic `C : CharSequence, C : R` receivers. */

@_cdecl("kk_string_get")
public func kk_string_get(_ strRaw: Int, _ indexRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard indexRaw >= 0, indexRaw < codeUnits.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(codeUnits.count)")
        )
        return 0
    }
    return Int(codeUnits[indexRaw])
}

@_cdecl("kk_char_sequence_get")
public func kk_char_sequence_get(
    _ sequenceRaw: Int,
    _ indexRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let codeUnits = runtimeCharSequenceUTF16Units(from: sequenceRaw) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "Value is not a CharSequence")
        )
        return 0
    }
    guard indexRaw >= 0, indexRaw < codeUnits.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(codeUnits.count)")
        )
        return 0
    }
    return Int(codeUnits[indexRaw])
}

@_cdecl("kk_char_sequence_subSequence")
public func kk_char_sequence_subSequence(
    _ sequenceRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let codeUnits = runtimeCharSequenceUTF16Units(from: sequenceRaw) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "Value is not a CharSequence")
        )
        return 0
    }
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= codeUnits.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(
                message: "startIndex=\(startIndex), endIndex=\(endIndex), length=\(codeUnits.count)"
            )
        )
        return 0
    }
    return runtimeMakeStringRaw(
        runtimeKotlinStringFromUTF16CodeUnits(Array(codeUnits[startIndex ..< endIndex]))
    )
}

@_cdecl("__kk_string_get_flat")
public func __kk_string_get_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ indexRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let lookup = runtimeFlatStringCodeUnit(
        data: data, length: length, byteCount: byteCount, hash: hash, index: indexRaw
    )
    guard let unit = lookup.unit else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(lookup.utf16Length)")
        )
        return 0
    }
    return Int(unit)
}

@_cdecl("__kk_string_getOrNull_flat")
public func __kk_string_getOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ indexRaw: Int
) -> Int {
    let lookup = runtimeFlatStringCodeUnit(
        data: data, length: length, byteCount: byteCount, hash: hash, index: indexRaw
    )
    guard let unit = lookup.unit else {
        return runtimeNullSentinelInt
    }
    return Int(unit)
}

@_cdecl("__kk_string_compareTo_member")
public func __kk_string_compareTo_member(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    return runtimeCompareStrings(lhs, rhs)
}

// KSP-413: compareTo(ignoreCase) and CharSequence?.contentEquals are bundled
// Kotlin source (Stdlib/kotlin/text/StringComparison.kt); the
// kk_string_compareToIgnoreCase / kk_string_contentEquals /
// kk_string_contentEquals_ignoreCase bridges were removed.
