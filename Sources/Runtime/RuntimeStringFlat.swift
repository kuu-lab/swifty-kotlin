// Flat String ABI wrappers.

import Foundation

func runtimeRegisterFlatStringResult(
    _ raw: Int,
    outLength: UnsafeMutablePointer<Int>?,
    outByteCount: UnsafeMutablePointer<Int>?,
    outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatString(
        runtimeStringFromRaw(raw) ?? "",
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

func runtimeStringUTF16CodeUnitsFromFlat(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> [UInt16] {
    Array(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash).utf16)
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

@_cdecl("kk_string_reversed_flat")
public func kk_string_reversed_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeRegisterFlatString(
        String(source.reversed()),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_repeat_flat")
public func kk_string_repeat_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ countRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    outThrown?.pointee = 0
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard countRaw >= 0 else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "Requested element count \(countRaw) is less than zero.")
        )
        return runtimeRegisterFlatString("", outLength: outLength, outByteCount: outByteCount, outHash: outHash)
    }
    return runtimeRegisterFlatString(
        String(repeating: source, count: countRaw),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_iterator_flat")
public func kk_string_iterator_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_iterator(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_first_flat")
public func kk_string_first_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let first = codeUnits.first else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return Int(first)
}

@_cdecl("kk_string_last_flat")
public func kk_string_last_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let last = codeUnits.last else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        return 0
    }
    return Int(last)
}

@_cdecl("kk_string_single_flat")
public func kk_string_single_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard codeUnits.count == 1 else {
        if codeUnits.isEmpty {
            runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        } else {
            runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Char sequence has more than one element."))
        }
        return 0
    }
    return Int(codeUnits[0])
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

@_cdecl("kk_string_firstOrNull_flat")
public func kk_string_firstOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let first = codeUnits.first else { return runtimeNullSentinelInt }
    return Int(first)
}

@_cdecl("kk_string_lastOrNull_flat")
public func kk_string_lastOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let last = codeUnits.last else { return runtimeNullSentinelInt }
    return Int(last)
}

@_cdecl("kk_string_singleOrNull_flat")
public func kk_string_singleOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    guard codeUnits.count == 1 else { return runtimeNullSentinelInt }
    return Int(codeUnits[0])
}

@_cdecl("kk_string_toBoolean_flat")
public func kk_string_toBoolean_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return source.caseInsensitiveCompare("true") == .orderedSame ? 1 : 0
}

@_cdecl("kk_string_toBooleanStrict_flat")
public func kk_string_toBooleanStrict_flat(
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

@_cdecl("kk_string_toBooleanStrictOrNull_flat")
public func kk_string_toBooleanStrictOrNull_flat(
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

@_cdecl("kk_string_toInt_flat")
public func kk_string_toInt_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toInt(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_toInt_radix_flat")
public func kk_string_toInt_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toInt_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_toIntOrNull_flat")
public func kk_string_toIntOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toIntOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toIntOrNull_radix_flat")
public func kk_string_toIntOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toIntOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_toLong_flat")
public func kk_string_toLong_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toLong(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_toLongOrNull_flat")
public func kk_string_toLongOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toLongOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toShort_flat")
public func kk_string_toShort_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toShort(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_toShortOrNull_flat")
public func kk_string_toShortOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toShortOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toByte_flat")
public func kk_string_toByte_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toByte(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_toByte_radix_flat")
public func kk_string_toByte_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toByte_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_toByteOrNull_flat")
public func kk_string_toByteOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toByteOrNull(kk_string_from_flat(data, length, byteCount, hash))
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

@_cdecl("kk_string_toSortedSet_flat")
public func kk_string_toSortedSet_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let values = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash).map {
        RuntimeValue(charScalar: Int($0))
    }
    let deduped = runtimeDeduplicatePreservingOrder(values)
    let sorted = deduped.sorted { runtimeCompareValues($0, $1) < 0 }
    return registerRuntimeObject(RuntimeSetBox(values: sorted))
}

@_cdecl("kk_string_toCollection_flat")
public func kk_string_toCollection_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ destRaw: Int
) -> Int {
    let values = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash).map {
        RuntimeValue(charScalar: Int($0))
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for value in values {
        runtimeAppendToMutableCollection(destRaw, value)
    }
    return destRaw
}

@_cdecl("kk_string_toList_flat")
public func kk_string_toList_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let values = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash).map {
        RuntimeValue(charScalar: Int($0))
    }
    return registerRuntimeObject(RuntimeListBox(values: values))
}

@_cdecl("kk_string_toCharArray_flat")
public func kk_string_toCharArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let values = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash).map {
        RuntimeValue(charScalar: Int($0))
    }
    let box = RuntimeArrayBox(length: values.count)
    box.values = values
    return registerRuntimeObject(box)
}

@_cdecl("kk_string_toTypedArray_flat")
public func kk_string_toTypedArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let values = runtimeStringUTF16CodeUnitsFromFlat(data: data, length: length, byteCount: byteCount, hash: hash).map {
        RuntimeValue(charScalar: Int($0))
    }
    let box = RuntimeArrayBox(length: values.count)
    box.values = values
    return registerRuntimeObject(box)
}

@_cdecl("kk_string_toUByteOrNull_radix_flat")
public func kk_string_toUByteOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toUByteOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_toUShortOrNull_radix_flat")
public func kk_string_toUShortOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toUShortOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_toUIntOrNull_radix_flat")
public func kk_string_toUIntOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toUIntOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_windowedSequence_partial_flat")
public func kk_string_windowedSequence_partial_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int
) -> Int {
    kk_string_windowedSequence_partial(kk_string_from_flat(data, length, byteCount, hash), size, step, partialWindows)
}

@_cdecl("kk_string_windowedSequence_transform_flat")
public func kk_string_windowedSequence_transform_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_windowedSequence_transform(kk_string_from_flat(data, length, byteCount, hash), size, step, partialWindows, fnPtr, closureRaw, outThrown)
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

@_cdecl("kk_string_chunked_flat")
public func kk_string_chunked_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int
) -> Int {
    runtimeStringChunkedList(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash), size: size)
}

@_cdecl("kk_string_chunked_sequence_flat")
public func kk_string_chunked_sequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int
) -> Int {
    runtimeStringChunkedSequence(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash), size: size)
}

@_cdecl("kk_string_chunked_sequence_transform_flat")
public func kk_string_chunked_sequence_transform_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return kk_string_chunked_sequence_transform(kk_string_from_flat(data, length, byteCount, hash), size, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_windowed_default_flat")
public func kk_string_windowed_default_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int
) -> Int {
    runtimeStringWindowedList(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash), size: size, step: 1)
}

@_cdecl("kk_string_windowed_flat")
public func kk_string_windowed_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int,
    _ step: Int
) -> Int {
    runtimeStringWindowedList(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash), size: size, step: step)
}

@_cdecl("kk_string_windowed_partial_flat")
public func kk_string_windowed_partial_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int
) -> Int {
    runtimeStringWindowedPartialList(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash), size: size, step: step, partialWindows: partialWindows)
}

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

@_cdecl("kk_string_asIterable_flat")
public func kk_string_asIterable_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringAsIterable(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash))
}

@_cdecl("kk_string_asSequence_flat")
public func kk_string_asSequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeStringAsSequence(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash))
}

@_cdecl("kk_string_contentEquals_flat")
public func kk_string_contentEquals_flat(
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

@_cdecl("kk_string_contentEquals_ignoreCase_flat")
public func kk_string_contentEquals_ignoreCase_flat(
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
    if data == nil || otherData == nil {
        return (data == nil && otherData == nil) ? 1 : 0
    }
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let other = runtimeStringFromFlatFields(data: otherData, length: otherLength, byteCount: otherByteCount, hash: otherHash)
    if ignoreCaseRaw != 0 {
        return source.caseInsensitiveCompare(other) == .orderedSame ? 1 : 0
    }
    return source == other ? 1 : 0
}

@_cdecl("kk_string_equalsIgnoreCase_flat")
public func kk_string_equalsIgnoreCase_flat(
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
    if data == nil || otherData == nil {
        return (data == nil && otherData == nil) ? 1 : 0
    }
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let other = runtimeStringFromFlatFields(data: otherData, length: otherLength, byteCount: otherByteCount, hash: otherHash)
    if ignoreCaseRaw == 0 {
        return source == other ? 1 : 0
    }
    return source.caseInsensitiveCompare(other) == .orderedSame ? 1 : 0
}
