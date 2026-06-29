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
        kk_string_trim(kk_string_from_flat(data, length, byteCount, hash)),
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
        kk_string_trim_predicate(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown),
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
            message: "IllegalArgumentException: Requested element count \(countRaw) is less than zero."
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

@_cdecl("kk_string_contains_str_flat")
public func kk_string_contains_str_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int
) -> Int {
    kk_string_contains_str(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash)
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
    kk_string_first(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_last_flat")
public func kk_string_last_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_last(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_single_flat")
public func kk_string_single_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_single(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_find_flat")
public func kk_string_find_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_find(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_findLast_flat")
public func kk_string_findLast_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_findLast(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_findAnyOf_flat")
public func kk_string_findAnyOf_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ stringsRaw: Int,
    _ startIndex: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_findAnyOf(kk_string_from_flat(data, length, byteCount, hash), stringsRaw, startIndex, ignoreCaseRaw)
}

@_cdecl("kk_string_findLastAnyOf_flat")
public func kk_string_findLastAnyOf_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ stringsRaw: Int,
    _ startIndex: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_findLastAnyOf(kk_string_from_flat(data, length, byteCount, hash), stringsRaw, startIndex, ignoreCaseRaw)
}

@_cdecl("kk_string_indexOf_flat")
public func kk_string_indexOf_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int
) -> Int {
    kk_string_indexOf(kk_string_from_flat(data, length, byteCount, hash), kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash))
}

@_cdecl("kk_string_indexOf_from_flat")
public func kk_string_indexOf_from_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int,
    _ startIndex: Int
) -> Int {
    kk_string_indexOf_from(kk_string_from_flat(data, length, byteCount, hash), kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash), startIndex)
}

@_cdecl("kk_string_indexOfAny_chars_flat")
public func kk_string_indexOfAny_chars_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsRaw: Int,
    _ startIndex: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_indexOfAny_chars(kk_string_from_flat(data, length, byteCount, hash), charsRaw, startIndex, ignoreCaseRaw)
}

@_cdecl("kk_string_indexOfAny_strings_flat")
public func kk_string_indexOfAny_strings_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ stringsRaw: Int,
    _ startIndex: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_indexOfAny_strings(kk_string_from_flat(data, length, byteCount, hash), stringsRaw, startIndex, ignoreCaseRaw)
}

@_cdecl("kk_string_lastIndexOf_flat")
public func kk_string_lastIndexOf_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int
) -> Int {
    kk_string_lastIndexOf(kk_string_from_flat(data, length, byteCount, hash), kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash))
}

@_cdecl("kk_string_lastIndexOf_char_flat")
public func kk_string_lastIndexOf_char_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charRaw: Int,
    _ startIndex: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_lastIndexOf_char(kk_string_from_flat(data, length, byteCount, hash), charRaw, startIndex, ignoreCaseRaw)
}

@_cdecl("kk_string_lastIndexOfAny_chars_flat")
public func kk_string_lastIndexOfAny_chars_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsRaw: Int,
    _ startIndex: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_lastIndexOfAny_chars(kk_string_from_flat(data, length, byteCount, hash), charsRaw, startIndex, ignoreCaseRaw)
}

@_cdecl("kk_string_lastIndexOfAny_strings_flat")
public func kk_string_lastIndexOfAny_strings_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ stringsRaw: Int,
    _ startIndex: Int,
    _ ignoreCaseRaw: Int
) -> Int {
    kk_string_lastIndexOfAny_strings(kk_string_from_flat(data, length, byteCount, hash), stringsRaw, startIndex, ignoreCaseRaw)
}

@_cdecl("kk_string_isEmpty_flat")
public func kk_string_isEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_isEmpty(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_isNotEmpty_flat")
public func kk_string_isNotEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_isNotEmpty(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_isBlank_flat")
public func kk_string_isBlank_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_isBlank(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_isNotBlank_flat")
public func kk_string_isNotBlank_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_isNotBlank(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_firstOrNull_flat")
public func kk_string_firstOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_firstOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_lastOrNull_flat")
public func kk_string_lastOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_lastOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_singleOrNull_flat")
public func kk_string_singleOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_singleOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_lines_flat")
public func kk_string_lines_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_lines(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toBoolean_flat")
public func kk_string_toBoolean_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toBoolean(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toBooleanStrict_flat")
public func kk_string_toBooleanStrict_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toBooleanStrict(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_toBooleanStrictOrNull_flat")
public func kk_string_toBooleanStrictOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toBooleanStrictOrNull(kk_string_from_flat(data, length, byteCount, hash))
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

@_cdecl("kk_string_toFloat_flat")
public func kk_string_toFloat_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_toFloat(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("kk_string_toFloatOrNull_flat")
public func kk_string_toFloatOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toFloatOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toSortedSet_flat")
public func kk_string_toSortedSet_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toSortedSet(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toCollection_flat")
public func kk_string_toCollection_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ destRaw: Int
) -> Int {
    kk_string_toCollection(kk_string_from_flat(data, length, byteCount, hash), destRaw)
}

@_cdecl("kk_string_toList_flat")
public func kk_string_toList_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toList(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toCharArray_flat")
public func kk_string_toCharArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toCharArray(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_toTypedArray_flat")
public func kk_string_toTypedArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_toTypedArray(kk_string_from_flat(data, length, byteCount, hash))
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

@_cdecl("kk_string_lineSequence_flat")
public func kk_string_lineSequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_lineSequence(kk_string_from_flat(data, length, byteCount, hash))
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
        kk_string_trimStart(kk_string_from_flat(data, length, byteCount, hash)),
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
        kk_string_trimStart_predicate(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown),
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
        kk_string_trimEnd(kk_string_from_flat(data, length, byteCount, hash)),
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
        kk_string_trimEnd_predicate(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_endsWith_flat")
public func kk_string_endsWith_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ suffixData: UnsafePointer<UInt8>?,
    _ suffixLength: Int,
    _ suffixByteCount: Int,
    _ suffixHash: Int
) -> Int {
    kk_string_endsWith(kk_string_from_flat(data, length, byteCount, hash), kk_string_from_flat(suffixData, suffixLength, suffixByteCount, suffixHash))
}

@_cdecl("kk_string_chunked_flat")
public func kk_string_chunked_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int
) -> Int {
    kk_string_chunked(kk_string_from_flat(data, length, byteCount, hash), size)
}

@_cdecl("kk_string_chunked_sequence_flat")
public func kk_string_chunked_sequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int
) -> Int {
    kk_string_chunked_sequence(kk_string_from_flat(data, length, byteCount, hash), size)
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
    kk_string_chunked_sequence_transform(kk_string_from_flat(data, length, byteCount, hash), size, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_windowed_default_flat")
public func kk_string_windowed_default_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ size: Int
) -> Int {
    kk_string_windowed_default(kk_string_from_flat(data, length, byteCount, hash), size)
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
    kk_string_windowed(kk_string_from_flat(data, length, byteCount, hash), size, step)
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
    kk_string_windowed_partial(kk_string_from_flat(data, length, byteCount, hash), size, step, partialWindows)
}

@_cdecl("kk_string_substring_flat")
public func kk_string_substring_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ hasEndRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substring(
        kk_string_from_flat(data, length, byteCount, hash),
        startRaw,
        endRaw,
        hasEndRaw,
        outThrown
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_take_flat")
public func kk_string_take_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ nRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_take(kk_string_from_flat(data, length, byteCount, hash), nRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_drop_flat")
public func kk_string_drop_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ nRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_drop(kk_string_from_flat(data, length, byteCount, hash), nRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_dropLast_flat")
public func kk_string_dropLast_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ nRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_dropLast(kk_string_from_flat(data, length, byteCount, hash), nRaw, outThrown),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_takeLast_flat")
public func kk_string_takeLast_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ nRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_takeLast(kk_string_from_flat(data, length, byteCount, hash), nRaw, outThrown),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

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
        kk_string_replace(
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
        kk_string_replace_char(kk_string_from_flat(data, length, byteCount, hash), oldCharRaw, newCharRaw),
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
        kk_string_replace_ignoreCase(
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
        kk_string_replace_char_ignoreCase(
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

@_cdecl("kk_string_replaceFirstChar_flat")
public func kk_string_replaceFirstChar_flat(
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
        kk_string_replaceFirstChar(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown),
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
    kk_string_asIterable(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_asSequence_flat")
public func kk_string_asSequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_asSequence(kk_string_from_flat(data, length, byteCount, hash))
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
    kk_string_contentEquals(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash)
    )
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
    kk_string_contentEquals_ignoreCase(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash),
        ignoreCaseRaw
    )
}

@_cdecl("kk_string_commonPrefixWith_flat")
public func kk_string_commonPrefixWith_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_commonPrefixWith(
            kk_string_from_flat(data, length, byteCount, hash),
            kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash)
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_commonSuffixWith_flat")
public func kk_string_commonSuffixWith_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_commonSuffixWith(
            kk_string_from_flat(data, length, byteCount, hash),
            kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash)
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_commonPrefixWith_ignoreCase_flat")
public func kk_string_commonPrefixWith_ignoreCase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int,
    _ ignoreCaseRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_commonPrefixWith_ignoreCase(
            kk_string_from_flat(data, length, byteCount, hash),
            kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash),
            ignoreCaseRaw
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_commonSuffixWith_ignoreCase_flat")
public func kk_string_commonSuffixWith_ignoreCase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int,
    _ ignoreCaseRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_commonSuffixWith_ignoreCase(
            kk_string_from_flat(data, length, byteCount, hash),
            kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash),
            ignoreCaseRaw
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
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
    kk_string_equalsIgnoreCase(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash),
        ignoreCaseRaw
    )
}
