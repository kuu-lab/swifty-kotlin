// String query and predicate functions (first/last/single, isEmpty/isBlank,
// ifBlank/ifEmpty, get, compareTo, contentEquals, lines, trimStart/trimEnd).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

// MARK: - STDLIB-190: first / last / single / firstOrNull / lastOrNull

@_cdecl("kk_string_first")
public func kk_string_first(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let first = codeUnits.first else {
        runtimeSetThrown(outThrown, message: "Char sequence is empty.")
        return 0
    }
    return kk_box_char(Int(first))
}

@_cdecl("kk_string_last")
public func kk_string_last(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard let last = codeUnits.last else {
        runtimeSetThrown(outThrown, message: "Char sequence is empty.")
        return 0
    }
    return kk_box_char(Int(last))
}

@_cdecl("kk_string_single")
public func kk_string_single(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard codeUnits.count == 1 else {
        let msg = codeUnits.isEmpty
            ? "Char sequence is empty."
            : "Char sequence has more than one element."
        runtimeSetThrown(outThrown, message: msg)
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

// MARK: - STDLIB-187: isEmpty / isNotEmpty / isBlank / isNotBlank

@_cdecl("kk_string_isEmpty")
public func kk_string_isEmpty(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.isEmpty ? 1 : 0)
}

@_cdecl("kk_string_isNotEmpty")
public func kk_string_isNotEmpty(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.isEmpty ? 0 : 1)
}

@_cdecl("kk_string_isBlank")
public func kk_string_isBlank(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0)
}

@_cdecl("kk_string_isNotBlank")
public func kk_string_isNotBlank(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return kk_box_bool(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
}

// MARK: - STDLIB-TEXT-EDGE-004: CharSequence.ifBlank(defaultValue)

@_cdecl("kk_string_ifBlank")
public func kk_string_ifBlank(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return strRaw
    }
    guard fnPtr != 0 else {
        return runtimeMakeStringRaw("")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifBlank defaultValue"
        )
        return runtimeMakeStringRaw("")
    }
    return result
}

// MARK: - STDLIB-TEXT-EDGE-005: CharSequence.ifEmpty(defaultValue)

@_cdecl("kk_string_ifEmpty")
public func kk_string_ifEmpty(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard source.isEmpty else {
        return strRaw
    }
    guard fnPtr != 0 else {
        return runtimeMakeStringRaw("")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "ifEmpty defaultValue"
        )
        return runtimeMakeStringRaw("")
    }
    return result
}

@_cdecl("kk_string_get")
public func kk_string_get(_ strRaw: Int, _ indexRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard indexRaw >= 0, indexRaw < scalars.count else {
        runtimeSetThrown(
            outThrown,
            message: "StringIndexOutOfBoundsException: index=\(indexRaw), length=\(scalars.count)"
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
            message: "StringIndexOutOfBoundsException: index=\(indexRaw), length=\(scalars.count)"
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

@_cdecl("kk_string_compareToIgnoreCase")
public func kk_string_compareToIgnoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    if ignoreCaseRaw == 0 {
        return runtimeCompareStrings(lhs, rhs)
    }
    let comparison = lhs.caseInsensitiveCompare(rhs)
    switch comparison {
    case .orderedAscending:
        return -1
    case .orderedDescending:
        return 1
    case .orderedSame:
        return 0
    }
}

@_cdecl("kk_string_compareToIgnoreCase_flat")
public func kk_string_compareToIgnoreCase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_compareToIgnoreCase(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash),
        ignoreCaseRaw
    )
}

// MARK: - STDLIB-TEXT-EDGE-009: CharSequence?.contentEquals

@_cdecl("kk_string_contentEquals")
public func kk_string_contentEquals(_ receiverRaw: Int, _ otherRaw: Int) -> Int {
    let receiverIsNull = (receiverRaw == runtimeNullSentinelInt)
    let otherIsNull = (otherRaw == runtimeNullSentinelInt)
    if receiverIsNull && otherIsNull {
        return kk_box_bool(1)
    }
    if receiverIsNull || otherIsNull {
        return kk_box_bool(0)
    }
    guard let receiverStr = runtimeStringFromRaw(receiverRaw),
          let otherStr = runtimeStringFromRaw(otherRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(receiverStr == otherStr ? 1 : 0)
}

@_cdecl("kk_string_contentEquals_ignoreCase")
public func kk_string_contentEquals_ignoreCase(_ receiverRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let receiverIsNull = (receiverRaw == runtimeNullSentinelInt)
    let otherIsNull = (otherRaw == runtimeNullSentinelInt)
    if receiverIsNull && otherIsNull {
        return kk_box_bool(1)
    }
    if receiverIsNull || otherIsNull {
        return kk_box_bool(0)
    }
    guard let receiverStr = runtimeStringFromRaw(receiverRaw),
          let otherStr = runtimeStringFromRaw(otherRaw) else {
        return kk_box_bool(0)
    }
    if ignoreCaseRaw == 0 {
        return kk_box_bool(receiverStr == otherStr ? 1 : 0)
    }
    return kk_box_bool(receiverStr.caseInsensitiveCompare(otherStr) == .orderedSame ? 1 : 0)
}

@_cdecl("kk_string_lines")
public func kk_string_lines(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringListRaw(runtimeNormalizedMultilineString(source))
}

@_cdecl("kk_string_lineSequence")
public func kk_string_lineSequence(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let lineRaws = runtimeNormalizedMultilineString(source).map(runtimeMakeStringRaw)
    let seq = RuntimeSequenceBox(steps: [.source(elements: lineRaws)])
    return registerRuntimeObject(seq)
}

@_cdecl("kk_string_trimStart")
public func kk_string_trimStart(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(String(source.drop { $0.isWhitespace }))
}

@_cdecl("kk_string_trimStart_predicate")
public func kk_string_trimStart_predicate(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringTrimWithPredicate(
        strRaw,
        fnPtr,
        closureRaw,
        outThrown,
        trimLeading: true,
        trimTrailing: false,
        context: "trimStart predicate"
    )
}

@_cdecl("kk_string_trimEnd")
public func kk_string_trimEnd(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(String(source.reversed().drop { $0.isWhitespace }.reversed()))
}

@_cdecl("kk_string_trimEnd_predicate")
public func kk_string_trimEnd_predicate(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringTrimWithPredicate(
        strRaw,
        fnPtr,
        closureRaw,
        outThrown,
        trimLeading: false,
        trimTrailing: true,
        context: "trimEnd predicate"
    )
}

// MARK: - STDLIB-TEXT-FN-044: String.random()

@_cdecl("kk_string_random")
public func kk_string_random(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard !codeUnits.isEmpty else {
        runtimeSetThrown(outThrown, message: "NoSuchElementException: Char sequence is empty.")
        return 0
    }
    let index = Int.random(in: 0 ..< codeUnits.count)
    return kk_box_char(Int(codeUnits[index]))
}

@_cdecl("kk_string_random_random")
public func kk_string_random_random(_ strRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard !codeUnits.isEmpty else {
        runtimeSetThrown(outThrown, message: "NoSuchElementException: Char sequence is empty.")
        return 0
    }
    let index = runtimeRandomIndex(count: codeUnits.count, randomRaw: randomRaw)
    return kk_box_char(Int(codeUnits[index]))
}
