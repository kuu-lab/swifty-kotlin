// String query and predicate functions (first/last/single,
// flat ifBlank/ifEmpty wrappers, get, compareTo, contentEquals, lines).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

@_cdecl("kk_char_sequence_length")
public func kk_char_sequence_length(_ raw: Int) -> Int {
    // Match the flat String aggregate length field used by String.length lowering.
    // The receiver may be any CharSequence implementation, so StringBuilder
    // handles are accepted in addition to String handles.
    if let text = runtimeCharSequenceText(from: raw) {
        return text.utf8.count
    }
    return runtimeStringFromRawOrPanic(raw, caller: #function).utf8.count
}

// MARK: - STDLIB-190: first / last / single / firstOrNull / lastOrNull

@_cdecl("kk_string_first")
public func kk_string_first(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let first = codeUnits.first else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return kk_box_char(Int(first))
}

@_cdecl("kk_string_last")
public func kk_string_last(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let last = codeUnits.last else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return kk_box_char(Int(last))
}

@_cdecl("kk_string_single")
public func kk_string_single(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard codeUnits.count == 1 else {
        if codeUnits.isEmpty {
            runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        } else {
            runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Char sequence has more than one element."))
        }
        return 0
    }
    return kk_box_char(Int(codeUnits[0]))
}

@_cdecl("kk_string_firstOrNull")
public func kk_string_firstOrNull(_ strRaw: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let first = codeUnits.first else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(first))
}

@_cdecl("kk_string_lastOrNull")
public func kk_string_lastOrNull(_ strRaw: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let last = codeUnits.last else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(last))
}

@_cdecl("kk_string_singleOrNull")
public func kk_string_singleOrNull(_ strRaw: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard codeUnits.count == 1 else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(codeUnits[0]))
}

@_cdecl("kk_string_getOrNull")
public func kk_string_getOrNull(_ strRaw: Int, _ index: Int) -> Int {
    let scalars = runtimeStringScalars(strRaw)
    guard index >= 0, index < scalars.count else {
        return runtimeNullSentinelInt
    }
    return kk_box_char(Int(scalars[index].value))
}

// MARK: - Flat ABI wrappers

@_cdecl("kk_string_ifBlank_flat")
public func kk_string_ifBlank_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ fnPtr: Int, _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    outThrown?.pointee = 0
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return runtimeRegisterFlatString(source, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard fnPtr != 0 else {
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let raw = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifBlank defaultValue"
        )
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_ifEmpty_flat")
public func kk_string_ifEmpty_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ fnPtr: Int, _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    outThrown?.pointee = 0
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard source.isEmpty else {
        return runtimeRegisterFlatString(source, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard fnPtr != 0 else {
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let raw = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifEmpty defaultValue"
        )
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_get")
public func kk_string_get(_ strRaw: Int, _ indexRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard indexRaw >= 0, indexRaw < scalars.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(scalars.count)")
        )
        return 0
    }
    return Int(scalars[indexRaw].value)
}

@_cdecl("kk_char_sequence_get")
public func kk_char_sequence_get(
    _ sequenceRaw: Int,
    _ indexRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let text = runtimeCharSequenceText(from: sequenceRaw) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "Value is not a CharSequence")
        )
        return 0
    }
    let scalars = Array(text.unicodeScalars)
    guard indexRaw >= 0, indexRaw < scalars.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(scalars.count)")
        )
        return 0
    }
    return Int(scalars[indexRaw].value)
}

@_cdecl("kk_string_get_flat")
public func kk_string_get_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ indexRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = Array(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash).unicodeScalars)
    guard indexRaw >= 0, indexRaw < scalars.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "index=\(indexRaw), length=\(scalars.count)")
        )
        return 0
    }
    return Int(scalars[indexRaw].value)
}

@_cdecl("kk_string_getOrNull_flat")
public func kk_string_getOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ indexRaw: Int
) -> Int {
    let scalars = Array(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash).unicodeScalars)
    guard indexRaw >= 0, indexRaw < scalars.count else {
        return runtimeNullSentinelInt
    }
    return Int(scalars[indexRaw].value)
}

@_cdecl("kk_string_compareTo_member")
public func kk_string_compareTo_member(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    return runtimeCompareStrings(lhs, rhs)
}

// KSP-413: compareTo(ignoreCase) and CharSequence?.contentEquals are bundled
// Kotlin source (Stdlib/kotlin/text/StringComparison.kt); the
// kk_string_compareToIgnoreCase / kk_string_contentEquals /
// kk_string_contentEquals_ignoreCase bridges were removed.

// MARK: - STDLIB-TEXT-FN-044: String.random()

@_cdecl("__kk_string_random")
public func __kk_string_random(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard !codeUnits.isEmpty else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    let index = Int.random(in: 0 ..< codeUnits.count)
    return kk_box_char(Int(codeUnits[index]))
}

@_cdecl("__kk_string_random_random")
public func __kk_string_random_random(_ strRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard !codeUnits.isEmpty else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    let index = runtimeRandomIndex(count: codeUnits.count, randomRaw: randomRaw)
    return kk_box_char(Int(codeUnits[index]))
}
