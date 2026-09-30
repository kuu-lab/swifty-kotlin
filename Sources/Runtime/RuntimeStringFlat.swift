// Flat String ABI wrappers.

import Foundation
import RuntimeABI

/// Flat result view of a boxed string handle: shares the box's cached flat
/// storage so repeated raw→flat bridges of the same value do not accumulate a
/// fresh buffer per call. Unresolvable handles still flatten to "".
func runtimeRegisterFlatStringResult(
    _ raw: Int,
    outLength: UnsafeMutablePointer<Int>?,
    outByteCount: UnsafeMutablePointer<Int>?,
    outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    if let data = kk_string_to_flat(raw, outLength, outByteCount, outHash) {
        return data
    }
    return runtimeRegisterFlatString(
        "",
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

func runtimeStringScalarsFromFlat(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> [UnicodeScalar] {
    Array(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash).unicodeScalars)
}

/// Single-index code-unit read for the flat string ABI. Runtime-registered
/// strings share the cached unit array on their storage; other buffers decode
/// scalars until the target index without materializing the whole array.
/// `unit` is nil exactly when `index` is out of bounds, and `utf16Length` then
/// carries the authoritative length for the bounds-error message.
func runtimeFlatStringCodeUnit(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int,
    index: Int
) -> (unit: UInt16?, utf16Length: Int) {
    if let units = runtimeFlatStringRegisteredUTF16CodeUnits(data: data) {
        if index >= 0, index < units.count {
            return (units[index], units.count)
        }
        return (nil, units.count)
    }
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    if let unit = runtimeKotlinStringUTF16CodeUnit(source, at: index) {
        return (unit, -1)
    }
    return (nil, runtimeKotlinStringUTF16Length(source))
}

/// Boundary code-unit reads for the flat string ABI. Registered strings share
/// the cached unit array; other buffers read only the leading and trailing
/// UTF-16 units of the decoded string (surrogate markers mapped exactly like
/// `runtimeKotlinStringUTF16CodeUnits`) plus whether a second unit exists,
/// never materializing the whole code-unit array.
func runtimeFlatStringBoundaryCodeUnits(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> (first: UInt16?, last: UInt16?, hasMultipleUnits: Bool) {
    if let units = runtimeFlatStringRegisteredUTF16CodeUnits(data: data) {
        return (units.first, units.last, units.count > 1)
    }
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    func kotlinCodeUnit(_ unit: UInt16) -> UInt16 {
        UInt16(KotlinStringSurrogateEncoding.codeUnitValue(for: UInt32(unit)) ?? UInt32(unit))
    }
    let units = source.utf16
    return (
        units.first.map(kotlinCodeUnit),
        units.last.map(kotlinCodeUnit),
        units.dropFirst().first != nil
    )
}

@_cdecl("kk_string_trim_flat")
public func kk_string_trim_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringTrimWhitespace(
            kk_string_from_flat(data, length, byteCount, hash),
            trimLeading: true,
            trimTrailing: true
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_trim_predicate_flat")
public func kk_string_trim_predicate_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringTrimWithPredicate(
            kk_string_from_flat(data, length, byteCount, hash),
            fnPtr,
            closureRaw,
            outThrown,
            trimLeading: true,
            trimTrailing: true,
            context: "trim predicate"
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_lowercase_flat")
public func kk_string_lowercase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_lowercase(kk_string_from_flat(data, length, byteCount, hash)),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_uppercase_flat")
public func kk_string_uppercase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_uppercase(kk_string_from_flat(data, length, byteCount, hash)),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

// KSP-1394: repeat is bundled Kotlin source (StringBasics.kt); its runtime
// bridge was removed.
// KSP-1396: reversed is bundled Kotlin source (StringBasics.kt); its runtime
// bridge was removed.
@_cdecl("__kk_string_first_flat")
public func __kk_string_first_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let first = boundary.first else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return Int(first)
}

@_cdecl("__kk_string_last_flat")
public func __kk_string_last_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let last = boundary.last else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return Int(last)
}

@_cdecl("__kk_string_single_flat")
public func __kk_string_single_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let unit = boundary.first, !boundary.hasMultipleUnits else {
        if boundary.first == nil {
            runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        } else {
            runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Char sequence has more than one element."))
        }
        return 0
    }
    return Int(unit)
}

// KSP-408: indexOf/lastIndexOf/indexOfAny/lastIndexOfAny/findAnyOf/findLastAnyOf are
// bundled Kotlin source (StringIndexOf.kt); their flat runtime bridges were removed.
// KSP-410: find/findLast are bundled Kotlin source (StringHOF.kt); their flat runtime
// bridges were removed.

@_cdecl("kk_string_isEmpty_flat")
public func kk_string_isEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return source.isEmpty ? 1 : 0
}

@_cdecl("kk_string_isNotEmpty_flat")
public func kk_string_isNotEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return source.isEmpty ? 0 : 1
}

@_cdecl("kk_string_isBlank_flat")
public func kk_string_isBlank_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0
}

@_cdecl("kk_string_isNotBlank_flat")
public func kk_string_isNotBlank_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
}

@_cdecl("__kk_string_firstOrNull_flat")
public func __kk_string_firstOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let first = boundary.first else { return runtimeNullSentinelInt }
    return Int(first)
}

@_cdecl("__kk_string_lastOrNull_flat")
public func __kk_string_lastOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let last = boundary.last else { return runtimeNullSentinelInt }
    return Int(last)
}

@_cdecl("__kk_string_singleOrNull_flat")
public func __kk_string_singleOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let unit = boundary.first, !boundary.hasMultipleUnits else { return runtimeNullSentinelInt }
    return Int(unit)
}

@_cdecl("__kk_string_toBoolean_flat")
public func __kk_string_toBoolean_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return source.caseInsensitiveCompare("true") == .orderedSame ? 1 : 0
}

@_cdecl("__kk_string_toBooleanStrict_flat")
public func __kk_string_toBooleanStrict_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    switch source {
    case "true":
        return 1
    case "false":
        return 0
    default:
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "The string doesn't represent a boolean value: \(source)"))
        return 0
    }
}

@_cdecl("__kk_string_toBooleanStrictOrNull_flat")
public func __kk_string_toBooleanStrictOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    switch source {
    case "true":
        return 1
    case "false":
        return 0
    default:
        return runtimeNullSentinelInt
    }
}

@_cdecl("__kk_string_toInt_flat")
public func __kk_string_toInt_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toInt(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toInt_radix_flat")
public func __kk_string_toInt_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toInt_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toIntOrNull_flat")
public func __kk_string_toIntOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toIntOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toIntOrNull_radix_flat")
public func __kk_string_toIntOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toIntOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toLong_flat")
public func __kk_string_toLong_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toLong(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toLongOrNull_flat")
public func __kk_string_toLongOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toLongOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toShort_flat")
public func __kk_string_toShort_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toShort(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toShortOrNull_flat")
public func __kk_string_toShortOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toShortOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toByte_flat")
public func __kk_string_toByte_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toByte(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toByte_radix_flat")
public func __kk_string_toByte_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toByte_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toByteOrNull_flat")
public func __kk_string_toByteOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toByteOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toFloat_flat")
public func __kk_string_toFloat_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toFloat(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toFloatOrNull_flat")
public func __kk_string_toFloatOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toFloatOrNull(kk_string_from_flat(data, length, byteCount, hash))
}
@_cdecl("__kk_string_toUByteOrNull_radix_flat")
public func __kk_string_toUByteOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toUByteOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toUShortOrNull_radix_flat")
public func __kk_string_toUShortOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toUShortOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toUIntOrNull_radix_flat")
public func __kk_string_toUIntOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toUIntOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_trimStart_flat")
public func kk_string_trimStart_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringTrimWhitespace(
            kk_string_from_flat(data, length, byteCount, hash),
            trimLeading: true,
            trimTrailing: false
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_trimStart_predicate_flat")
public func kk_string_trimStart_predicate_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringTrimWithPredicate(
            kk_string_from_flat(data, length, byteCount, hash),
            fnPtr,
            closureRaw,
            outThrown,
            trimLeading: true,
            trimTrailing: false,
            context: "trimStart predicate"
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_trimEnd_flat")
public func kk_string_trimEnd_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringTrimWhitespace(
            kk_string_from_flat(data, length, byteCount, hash),
            trimLeading: false,
            trimTrailing: true
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_trimEnd_predicate_flat")
public func kk_string_trimEnd_predicate_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringTrimWithPredicate(
            kk_string_from_flat(data, length, byteCount, hash),
            fnPtr,
            closureRaw,
            outThrown,
            trimLeading: false,
            trimTrailing: true,
            context: "trimEnd predicate"
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

// KSP-404: kk_string_endsWith_flat removed; endsWith is bundled Kotlin source.

// KSP-406: substring/subSequence flat bridges removed with the bundled Kotlin
// source migration (StringSubstringSlice.kt).

// KSP-405: take/takeLast/drop/dropLast are bundled Kotlin source
// (StringTakeDrop.kt); their flat runtime bridges were removed.

@_cdecl("kk_string_replace_flat")
public func kk_string_replace_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ oldData: UnsafePointer<UInt8>?,
    _ oldLength: Int,
    _ oldByteCount: Int,
    _ oldHash: Int,
    _ newData: UnsafePointer<UInt8>?,
    _ newLength: Int,
    _ newByteCount: Int,
    _ newHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringReplace(
            kk_string_from_flat(data, length, byteCount, hash),
            kk_string_from_flat(oldData, oldLength, oldByteCount, oldHash),
            kk_string_from_flat(newData, newLength, newByteCount, newHash)
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_replace_char_flat")
public func kk_string_replace_char_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ oldCharRaw: Int,
    _ newCharRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringReplaceChar(kk_string_from_flat(data, length, byteCount, hash), oldCharRaw, newCharRaw),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_replace_ignoreCase_flat")
public func kk_string_replace_ignoreCase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ oldData: UnsafePointer<UInt8>?,
    _ oldLength: Int,
    _ oldByteCount: Int,
    _ oldHash: Int,
    _ newData: UnsafePointer<UInt8>?,
    _ newLength: Int,
    _ newByteCount: Int,
    _ newHash: Int,
    _ ignoreCaseRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringReplaceIgnoreCase(
            kk_string_from_flat(data, length, byteCount, hash),
            kk_string_from_flat(oldData, oldLength, oldByteCount, oldHash),
            kk_string_from_flat(newData, newLength, newByteCount, newHash),
            ignoreCaseRaw
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_replace_char_ignoreCase_flat")
public func kk_string_replace_char_ignoreCase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ oldCharRaw: Int,
    _ newCharRaw: Int,
    _ ignoreCaseRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringReplaceCharIgnoreCase(
            kk_string_from_flat(data, length, byteCount, hash),
            oldCharRaw,
            newCharRaw,
            ignoreCaseRaw
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}
// KSP-413: contentEquals / equals(ignoreCase) are bundled Kotlin source
// (Stdlib/kotlin/text/StringComparison.kt); the kk_string_contentEquals_flat /
// kk_string_contentEquals_ignoreCase_flat / kk_string_equalsIgnoreCase_flat
// bridges were removed.
