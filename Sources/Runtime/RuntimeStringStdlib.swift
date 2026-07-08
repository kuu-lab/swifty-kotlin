// Core string operations (trim, case, normalize, split, replace, substring,
// collection conversions, asIterable/asSequence, withIndex, replaceFirstChar,
// take/drop, removePrefix/removeSuffix, startsWith/endsWith, contains).
// Other string functions have been split into dedicated files:
//   RuntimeStringHelpers.swift    — shared internal helpers
//   RuntimeStringConversion.swift — toInt, toDouble, toLong, etc.
//   RuntimeStringSearch.swift     — indexOf, lastIndexOf, findAnyOf, etc.
//   RuntimeStringQuery.swift      — first/last, isEmpty/isBlank, compareTo, etc.
//   RuntimeStringSubstring.swift  — substringBefore/After, replaceFirst, etc.
//   RuntimeStringEncoding.swift   — charset constants, toByteArray, encode/decode
//   RuntimeStringFormat.swift     — String.format, indent operations
//   RuntimeStringHOF.swift        — iterator, filter/map/count, chunked/windowed/zip
//   RuntimeStringComparison.swift — kk_compare_any

import Foundation

func runtimeStringTrimWithPredicate(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    trimLeading: Bool,
    trimTrailing: Bool,
    context: String
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars))
    }

    func shouldTrim(_ scalar: UnicodeScalar) -> Bool? {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: context)
            return nil
        }
        return maybeUnbox(result) != 0
    }

    var start = 0
    var end = scalars.count
    if trimLeading {
        while start < end {
            guard let matches = shouldTrim(scalars[start]) else {
                return runtimeMakeStringRaw("")
            }
            guard matches else { break }
            start += 1
        }
    }
    if trimTrailing {
        while end > start {
            guard let matches = shouldTrim(scalars[end - 1]) else {
                return runtimeMakeStringRaw("")
            }
            guard matches else { break }
            end -= 1
        }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start ..< end]))
}

// MARK: - STDLIB-006/009/013 String Functions

// MARK: - STDLIB-TEXT-FN-026: intern

@_cdecl("kk_string_intern")
public func kk_string_intern(_ strRaw: Int) -> Int {
    return strRaw
}

@_cdecl("kk_string_trim")
public func kk_string_trim(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return runtimeMakeStringRaw(trimmed)
}

@_cdecl("kk_string_trim_predicate")
public func kk_string_trim_predicate(
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
        trimTrailing: true,
        context: "trim predicate"
    )
}

@_cdecl("kk_string_lowercase")
public func kk_string_lowercase(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(source.lowercased())
}

@_cdecl("kk_string_uppercase")
public func kk_string_uppercase(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(source.uppercased())
}

@_cdecl("kk_string_capitalize")
public func kk_string_capitalize(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard !source.isEmpty else { return strRaw }
    return runtimeMakeStringRaw(source.prefix(1).uppercased() + source.dropFirst())
}

@_cdecl("kk_string_lowercase_locale")
public func kk_string_lowercase_locale(_ strRaw: Int, _ localeRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        return runtimeMakeStringRaw(source.lowercased())
    }
    return runtimeMakeStringRaw(source.lowercased(with: box.locale))
}

@_cdecl("kk_string_lowercase_locale_flat")
public func kk_string_lowercase_locale_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ localeRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatString(
        runtimeStringFromRaw(kk_string_lowercase_locale(kk_string_from_flat(data, length, byteCount, hash), localeRaw)) ?? "",
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_uppercase_locale")
public func kk_string_uppercase_locale(_ strRaw: Int, _ localeRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        return runtimeMakeStringRaw(source.uppercased())
    }
    return runtimeMakeStringRaw(source.uppercased(with: box.locale))
}

@_cdecl("kk_string_uppercase_locale_flat")
public func kk_string_uppercase_locale_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ localeRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatString(
        runtimeStringFromRaw(kk_string_uppercase_locale(kk_string_from_flat(data, length, byteCount, hash), localeRaw)) ?? "",
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_compareTo_locale")
public func kk_string_compareTo_locale(_ lhsRaw: Int, _ rhsRaw: Int, _ localeRaw: Int) -> Int {
    let lhs = runtimeStringFromRawOrPanic(lhsRaw, caller: #function)
    let rhs = runtimeStringFromRawOrPanic(rhsRaw, caller: #function)
    let locale: Locale = runtimeLocaleBox(from: localeRaw)?.locale ?? Locale.current
    switch lhs.compare(rhs, options: [], range: nil, locale: locale) {
    case .orderedAscending:
        return -1
    case .orderedDescending:
        return 1
    case .orderedSame:
        return 0
    }
}

@_cdecl("kk_string_compareTo_locale_flat")
public func kk_string_compareTo_locale_flat(
    _ lhsData: UnsafePointer<UInt8>?,
    _ lhsLength: Int,
    _ lhsByteCount: Int,
    _ lhsHash: Int,
    _ rhsData: UnsafePointer<UInt8>?,
    _ rhsLength: Int,
    _ rhsByteCount: Int,
    _ rhsHash: Int,
    _ localeRaw: Int
) -> Int {
    kk_string_compareTo_locale(
        kk_string_from_flat(lhsData, lhsLength, lhsByteCount, lhsHash),
        kk_string_from_flat(rhsData, rhsLength, rhsByteCount, rhsHash),
        localeRaw
    )
}

private enum NormalizationFormTag: Int {
    case nfc = 0
    case nfd = 1
    case nfkc = 2
    case nfkd = 3
}

@_cdecl("__kk_normalization_form_nfc")
public func __kk_normalization_form_nfc() -> Int { NormalizationFormTag.nfc.rawValue }

@_cdecl("__kk_normalization_form_nfd")
public func __kk_normalization_form_nfd() -> Int { NormalizationFormTag.nfd.rawValue }

@_cdecl("__kk_normalization_form_nfkc")
public func __kk_normalization_form_nfkc() -> Int { NormalizationFormTag.nfkc.rawValue }

@_cdecl("__kk_normalization_form_nfkd")
public func __kk_normalization_form_nfkd() -> Int { NormalizationFormTag.nfkd.rawValue }

private func runtimeNormalizedString(_ source: String, formTagRaw: Int) -> String {
    guard let form = NormalizationFormTag(rawValue: formTagRaw) else {
        return source
    }
    switch form {
    case .nfc:
        return source.precomposedStringWithCanonicalMapping
    case .nfd:
        return source.decomposedStringWithCanonicalMapping
    case .nfkc:
        return source.precomposedStringWithCompatibilityMapping
    case .nfkd:
        return source.decomposedStringWithCompatibilityMapping
    }
}

@_cdecl("__kk_string_normalize")
public func __kk_string_normalize(_ strRaw: Int, _ formTagRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(runtimeNormalizedString(source, formTagRaw: formTagRaw))
}

@_cdecl("__kk_string_normalize_flat")
public func __kk_string_normalize_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ formTagRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatString(
        runtimeNormalizedString(runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash), formTagRaw: formTagRaw),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("__kk_string_isNormalized")
public func __kk_string_isNormalized(_ strRaw: Int, _ formTagRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let normalized = runtimeNormalizedString(source, formTagRaw: formTagRaw)
    return normalized.unicodeScalars.elementsEqual(source.unicodeScalars) ? 1 : 0
}

@_cdecl("__kk_string_isNormalized_flat")
public func __kk_string_isNormalized_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ formTagRaw: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let normalized = runtimeNormalizedString(source, formTagRaw: formTagRaw)
    return normalized.unicodeScalars.elementsEqual(source.unicodeScalars) ? 1 : 0
}

@_cdecl("kk_string_split")
public func kk_string_split(_ strRaw: Int, _ delimRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimRaw, caller: #function)

    if delimiter.isEmpty {
        return runtimeMakeStringListRaw([source])
    }
    return runtimeMakeStringListRaw(runtimeSplitString(source, delimiter: delimiter))
}

@_cdecl("__kk_string_split")
public func __kk_string_split(_ strRaw: Int, _ delimRaw: Int) -> Int {
    kk_string_split(strRaw, delimRaw)
}

@_cdecl("kk_string_split_flat")
public func kk_string_split_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ delimData: UnsafePointer<UInt8>?,
    _ delimLength: Int,
    _ delimByteCount: Int,
    _ delimHash: Int
) -> Int {
    kk_string_split(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimData, delimLength, delimByteCount, delimHash)
    )
}

// MARK: - STDLIB-TEXT-EDGE-001: CharSequence.split with ignoreCase and limit

@_cdecl("kk_string_split_limit")
public func kk_string_split_limit(_ strRaw: Int, _ delimRaw: Int, _ ignoreCaseRaw: Int, _ limitRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimRaw, caller: #function)
    let ignoreCase = ignoreCaseRaw != 0
    let limit = limitRaw

    if delimiter.isEmpty {
        return runtimeMakeStringListRaw([source])
    }
    return runtimeMakeStringListRaw(
        runtimeSplitStringLimit(source, delimiter: delimiter, ignoreCase: ignoreCase, limit: limit)
    )
}

@_cdecl("__kk_string_split_limit")
public func __kk_string_split_limit(_ strRaw: Int, _ delimRaw: Int, _ ignoreCaseRaw: Int, _ limitRaw: Int) -> Int {
    kk_string_split_limit(strRaw, delimRaw, ignoreCaseRaw, limitRaw)
}

@_cdecl("kk_string_split_limit_flat")
public func kk_string_split_limit_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ delimData: UnsafePointer<UInt8>?,
    _ delimLength: Int,
    _ delimByteCount: Int,
    _ delimHash: Int,
    _ ignoreCaseRaw: Int,
    _ limitRaw: Int
) -> Int {
    kk_string_split_limit(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimData, delimLength, delimByteCount, delimHash),
        ignoreCaseRaw,
        limitRaw
    )
}


func runtimeStringReplace(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldValue, with: newValue))
}

// MARK: - STDLIB-TEXT-FN-055: String.replace overloads

func runtimeStringReplaceChar(_ strRaw: Int, _ oldCharRaw: Int, _ newCharRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldStr = runtimeCharacterFromRaw(oldCharRaw)
    let newStr = runtimeCharacterFromRaw(newCharRaw)
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldStr, with: newStr))
}

func runtimeStringReplaceIgnoreCase(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
    let options: String.CompareOptions = ignoreCaseRaw != 0 ? [.caseInsensitive] : []
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldValue, with: newValue, options: options))
}

func runtimeStringReplaceCharIgnoreCase(_ strRaw: Int, _ oldCharRaw: Int, _ newCharRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldStr = runtimeCharacterFromRaw(oldCharRaw)
    let newStr = runtimeCharacterFromRaw(newCharRaw)
    let options: String.CompareOptions = ignoreCaseRaw != 0 ? [.caseInsensitive] : []
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldStr, with: newStr, options: options))
}

@_cdecl("kk_string_substring")
public func kk_string_substring(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ hasEndRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    let length = scalars.count
    let start = startRaw
    let hasEnd = hasEndRaw != 0
    let end = hasEnd ? endRaw : length

    if start < 0 || start > length || end < 0 || end > length || start > end {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(
                message: "start=\(start), end=\(hasEnd ? end : length), length=\(length)"
            )
        )
        return 0
    }

    let result = runtimeStringFromScalars(scalars[start ..< end])
    return runtimeMakeStringRaw(result)
}

@_cdecl("kk_string_subSequence")
public func kk_string_subSequence(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_substring(strRaw, startRaw, endRaw, 1, outThrown)
}

@_cdecl("kk_string_subSequence_flat")
public func kk_string_subSequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_subSequence(kk_string_from_flat(data, length, byteCount, hash), startRaw, endRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

// STDLIB-TEXT-FN-068: String.slice(indices: IntRange)
@_cdecl("kk_string_slice_range")
public func kk_string_slice_range(
    _ strRaw: Int,
    _ rangeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return runtimeMakeStringRaw("")
    }
    if range.first > range.last {
        return runtimeMakeStringRaw("")
    }
    return kk_string_substring(strRaw, range.first, range.last + 1, 1, outThrown)
}

// STDLIB-TEXT-FN-068: String.slice(indices: Iterable<Int>)
@_cdecl("kk_string_slice_iterable")
public func kk_string_slice_iterable(
    _ strRaw: Int,
    _ indicesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    let length = scalars.count
    let indexElements: [Int]
    if let indexList = runtimeListBox(from: indicesRaw) {
        indexElements = indexList.elements
    } else if let indexSet = runtimeSetBox(from: indicesRaw) {
        indexElements = indexSet.elements
    } else {
        return runtimeMakeStringRaw("")
    }
    var result: [UnicodeScalar] = []
    for rawIdx in indexElements {
        let idx = kk_unbox_int(rawIdx)
        if idx < 0 || idx >= length {
            runtimeSetThrown(
                outThrown,
                runtimeAllocateIndexOutOfBoundsException(message: "index \(idx) out of range [0, \(length))")
            )
            return 0
        }
        result.append(scalars[idx])
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(result))
}

private func runtimeStringCodePointCount(
    units: [UInt16],
    startIndex: Int,
    endIndex: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= units.count else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIndexOutOfBoundsException(message: "startIndex=\(startIndex), endIndex=\(endIndex), length=\(units.count)")
        )
        return 0
    }

    var count = 0
    var index = startIndex
    while index < endIndex {
        let unit = units[index]
        if unit >= 0xD800, unit <= 0xDBFF, index + 1 < endIndex {
            let next = units[index + 1]
            if next >= 0xDC00, next <= 0xDFFF {
                index += 2
                count += 1
                continue
            }
        }
        index += 1
        count += 1
    }
    return count
}

// MARK: - STDLIB-TEXT-FN-010: CharSequence.codePointCount

@_cdecl("__kk_string_codePointCount")
public func __kk_string_codePointCount(_ strRaw: Int) -> Int {
    let units = runtimeStringUTF16CodeUnits(strRaw)
    return runtimeStringCodePointCount(units: units, startIndex: 0, endIndex: units.count, outThrown: nil)
}

@_cdecl("__kk_string_codePointCount_from")
public func __kk_string_codePointCount_from(
    _ strRaw: Int,
    _ startIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let units = runtimeStringUTF16CodeUnits(strRaw)
    return runtimeStringCodePointCount(
        units: units,
        startIndex: startIndex,
        endIndex: units.count,
        outThrown: outThrown
    )
}

@_cdecl("__kk_string_codePointCount_range")
public func __kk_string_codePointCount_range(
    _ strRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let units = runtimeStringUTF16CodeUnits(strRaw)
    return runtimeStringCodePointCount(
        units: units,
        startIndex: startIndex,
        endIndex: endIndex,
        outThrown: outThrown
    )
}

@_cdecl("kk_string_toList")
public func kk_string_toList(_ strRaw: Int) -> Int {
    let charValues = runtimeStringUTF16CodeUnits(strRaw).map { RuntimeValue(charScalar: Int($0)) }
    return registerRuntimeObject(RuntimeListBox(values: charValues))
}
@_cdecl("kk_string_toMutableList")
public func kk_string_toMutableList(_ strRaw: Int) -> Int {
    let charValues = runtimeStringUTF16CodeUnits(strRaw).map { RuntimeValue(charScalar: Int($0)) }
    return registerRuntimeObject(RuntimeListBox(values: charValues))
}
@_cdecl("kk_string_toCharArray")
public func kk_string_toCharArray(_ strRaw: Int) -> Int {
    let charValues = runtimeStringUTF16CodeUnits(strRaw).map { RuntimeValue(charScalar: Int($0)) }
    let box = RuntimeArrayBox(length: charValues.count)
    box.values = charValues
    return registerRuntimeObject(box)
}
@_cdecl("kk_string_toTypedArray")
public func kk_string_toTypedArray(_ strRaw: Int) -> Int {
    let charValues = runtimeStringUTF16CodeUnits(strRaw).map { RuntimeValue(charScalar: Int($0)) }
    let box = RuntimeArrayBox(length: charValues.count)
    box.values = charValues
    return registerRuntimeObject(box)
}
@_cdecl("kk_string_toCollection")
public func kk_string_toCollection(_ strRaw: Int, _ destRaw: Int) -> Int {
    let charValues = runtimeStringUTF16CodeUnits(strRaw).map { RuntimeValue(charScalar: Int($0)) }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for charValue in charValues {
        runtimeAppendToMutableCollection(destRaw, charValue)
    }
    return destRaw
}
@_cdecl("kk_string_toSortedSet")
public func kk_string_toSortedSet(_ strRaw: Int) -> Int {
    let charValues = runtimeStringUTF16CodeUnits(strRaw).map { RuntimeValue(charScalar: Int($0)) }
    let deduped = runtimeDeduplicatePreservingOrder(charValues)
    let sorted = deduped.sorted { runtimeCompareValues($0, $1) < 0 }
    return registerRuntimeObject(RuntimeSetBox(values: sorted))
}
@_cdecl("kk_chararray_concatToString")
public func kk_chararray_concatToString(_ arrRaw: Int) -> Int {
    guard let box = runtimeArrayBox(from: arrRaw) else {
        return runtimeMakeStringRaw("")
    }
    var scalars = String.UnicodeScalarView()
    for i in 0..<box.elements.count {
        let charValue = kk_unbox_char(box.elements[i])
        if let scalar = UnicodeScalar(charValue) {
            scalars.append(scalar)
        }
    }
    return runtimeMakeStringRaw(String(scalars))
}

// MARK: - STDLIB-317: String.asIterable() — lazy Iterable<Char> view

/// Returns a lazy `Iterable<Char>` wrapper around the given string.
/// Character materialisation is deferred until the iterable is actually consumed
/// (e.g. via `iterator()`, `toList()`, or `for-in`).  Creation is O(1).
func runtimeStringAsIterable(_ source: String) -> Int {
    registerRuntimeObject(RuntimeStringIterableBox(source: source))
}

@_cdecl("kk_string_asIterable")
public func kk_string_asIterable(_ strRaw: Int) -> Int {
    runtimeStringAsIterable(runtimeStringFromRawOrPanic(strRaw, caller: #function))
}

/// Materialise the lazy string-iterable into a `List<Char>`.
/// Called when `toList()` is invoked on the iterable returned by `asIterable()`,
/// or when the for-in lowering needs a concrete list.
@_cdecl("kk_string_iterable_toList")
public func kk_string_iterable_toList(_ iterableRaw: Int) -> Int {
    guard let box = runtimeStringIterableBox(from: iterableRaw) else {
        // Only the lazy iterable wrapper is accepted; legacy raw string handles
        // must not be reinterpreted as iterables.
        return kk_string_toList(runtimeMakeStringRaw(""))
    }
    return kk_string_toList(runtimeMakeStringRaw(box.source))
}

/// Create an iterator from a lazy string iterable (for `for (c in str.asIterable())`).
@_cdecl("kk_string_iterable_iterator")
public func kk_string_iterable_iterator(_ iterableRaw: Int) -> Int {
    if let box = runtimeStringIterableBox(from: iterableRaw) {
        return kk_string_iterator(runtimeMakeStringRaw(box.source))
    }
    // Only the lazy iterable wrapper is accepted; legacy raw string handles
    // must not be reinterpreted as iterables. Return an empty iterator.
    let box = RuntimeStringIteratorBox(charRaws: [])
    return registerRuntimeObject(box)
}

func runtimeStringAsSequence(_ source: String) -> Int {
    // Lazy: store only the string handle; characters are yielded on demand
    registerRuntimeObject(RuntimeSequenceBox(steps: [.stringSource(source: source)]))
}

@_cdecl("kk_string_asSequence")
public func kk_string_asSequence(_ strRaw: Int) -> Int {
    runtimeStringAsSequence(runtimeStringFromRawOrPanic(strRaw, caller: #function))
}

// MARK: - STDLIB-TEXT-FN-115: CharSequence.withIndex() — Iterable<IndexedValue<Char>>

/// Returns an `Iterable<IndexedValue<Char>>` that wraps each UTF-16 code unit with its index.
/// Each element is an `IndexedValue<Char>` represented as a `RuntimePairBox(index, boxedChar)`.
/// The list is materialised eagerly (strings are immutable).
@_cdecl("kk_string_withIndex")
public func kk_string_withIndex(_ strRaw: Int) -> Int {
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    var elements: [Int] = []
    elements.reserveCapacity(codeUnits.count)
    for (idx, codeUnit) in codeUnits.enumerated() {
        let charRaw = kk_box_char(Int(codeUnit))
        elements.append(runtimeIndexedValueNew(index: idx, value: charRaw))
    }
    return runtimeMakeListRaw(elements)
}

@_cdecl("kk_string_withIndex_flat")
public func kk_string_withIndex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_withIndex(kk_string_from_flat(data, length, byteCount, hash))
}


// MARK: - STDLIB-315: String.replaceFirstChar

@_cdecl("kk_string_replaceFirstChar")
public func kk_string_replaceFirstChar(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else { return runtimeMakeStringRaw("") }
    guard fnPtr != 0 else { return strRaw }
    let firstCharRaw = Int(scalars[0].value)
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, firstCharRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "replaceFirstChar transform"
        )
        return runtimeMakeStringRaw("")
    }
    let replacement = runtimeUnicodeScalarFromRaw(result) ?? scalars[0]
    let tail = scalars.dropFirst()
    var rebuilt = String.UnicodeScalarView()
    rebuilt.append(replacement)
    rebuilt.append(contentsOf: tail)
    return runtimeMakeStringRaw(String(rebuilt))
}

@_cdecl("kk_string_take")
public func kk_string_take(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Requested element count \(nRaw) is less than zero."))
        return runtimeMakeStringRaw("")
    }
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw("")
    }
    guard nRaw < scalars.count else {
        return runtimeMakeStringRaw(source)
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< nRaw]))
}

// MARK: - STDLIB-185: removePrefix / removeSuffix / removeSurrounding

@_cdecl("kk_string_removePrefix")
public func kk_string_removePrefix(_ strRaw: Int, _ prefixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let prefix = runtimeStringFromRawOrPanic(prefixRaw, caller: #function)
    guard source.hasPrefix(prefix) else {
        return runtimeMakeStringRaw(source)
    }
    return runtimeMakeStringRaw(String(source.dropFirst(prefix.count)))
}

@_cdecl("kk_string_removeSuffix")
public func kk_string_removeSuffix(_ strRaw: Int, _ suffixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let suffix = runtimeStringFromRawOrPanic(suffixRaw, caller: #function)
    guard source.hasSuffix(suffix) else {
        return runtimeMakeStringRaw(source)
    }
    return runtimeMakeStringRaw(String(source.dropLast(suffix.count)))
}

@_cdecl("kk_string_removeSurrounding")
public func kk_string_removeSurrounding(_ strRaw: Int, _ delimiterRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    guard !delimiter.isEmpty,
          source.hasPrefix(delimiter),
          source.hasSuffix(delimiter),
          source.count >= delimiter.count * 2
    else {
        return runtimeMakeStringRaw(source)
    }
    let start = source.index(source.startIndex, offsetBy: delimiter.count)
    let end = source.index(source.endIndex, offsetBy: -delimiter.count)
    return runtimeMakeStringRaw(String(source[start ..< end]))
}

@_cdecl("kk_string_removeSurrounding_pair")
public func kk_string_removeSurrounding_pair(
    _ strRaw: Int,
    _ prefixRaw: Int,
    _ suffixRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let prefix = runtimeStringFromRawOrPanic(prefixRaw, caller: #function)
    let suffix = runtimeStringFromRawOrPanic(suffixRaw, caller: #function)
    guard source.hasPrefix(prefix),
          source.hasSuffix(suffix),
          source.count >= prefix.count + suffix.count
    else {
        return runtimeMakeStringRaw(source)
    }
    let start = source.index(source.startIndex, offsetBy: prefix.count)
    let end = source.index(source.endIndex, offsetBy: -suffix.count)
    return runtimeMakeStringRaw(String(source[start ..< end]))
}

// MARK: - Flat ABI wrappers

@_cdecl("kk_string_removePrefix_flat")
public func kk_string_removePrefix_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ prefixData: UnsafePointer<UInt8>?, _ prefixLength: Int, _ prefixByteCount: Int, _ prefixHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_removePrefix(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(prefixData, prefixLength, prefixByteCount, prefixHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_removeSuffix_flat")
public func kk_string_removeSuffix_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ suffixData: UnsafePointer<UInt8>?, _ suffixLength: Int, _ suffixByteCount: Int, _ suffixHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_removeSuffix(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(suffixData, suffixLength, suffixByteCount, suffixHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_removeSurrounding_flat")
public func kk_string_removeSurrounding_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_removeSurrounding(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_removeSurrounding_pair_flat")
public func kk_string_removeSurrounding_pair_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ prefixData: UnsafePointer<UInt8>?, _ prefixLength: Int, _ prefixByteCount: Int, _ prefixHash: Int,
    _ suffixData: UnsafePointer<UInt8>?, _ suffixLength: Int, _ suffixByteCount: Int, _ suffixHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_removeSurrounding_pair(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(prefixData, prefixLength, prefixByteCount, prefixHash),
        kk_string_from_flat(suffixData, suffixLength, suffixByteCount, suffixHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_takeLast")
public func kk_string_takeLast(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Requested element count \(nRaw) is less than zero."))
        return runtimeMakeStringRaw("")
    }
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw("")
    }
    let start = max(0, scalars.count - nRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start ..< scalars.count]))
}

@_cdecl("kk_string_drop")
public func kk_string_drop(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Requested element count \(nRaw) is less than zero."))
        return runtimeMakeStringRaw("")
    }
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw(source)
    }
    if nRaw >= scalars.count {
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[nRaw ..< scalars.count]))
}

@_cdecl("kk_string_dropLast")
public func kk_string_dropLast(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Requested element count \(nRaw) is less than zero."))
        return runtimeMakeStringRaw("")
    }
    let scalars = runtimeStringScalars(strRaw)
    guard nRaw > 0 else {
        return runtimeMakeStringRaw(source)
    }
    let end = max(0, scalars.count - nRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< end]))
}

@_cdecl("kk_string_startsWith")
public func kk_string_startsWith(_ strRaw: Int, _ prefixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let prefix = runtimeStringFromRawOrPanic(prefixRaw, caller: #function)
    return kk_box_bool(source.hasPrefix(prefix) ? 1 : 0)
}

@_cdecl("kk_string_startsWith_flat")
public func kk_string_startsWith_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ prefixData: UnsafePointer<UInt8>?,
    _ prefixLength: Int,
    _ prefixByteCount: Int,
    _ prefixHash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let prefix = runtimeStringFromFlatFields(data: prefixData, length: prefixLength, byteCount: prefixByteCount, hash: prefixHash)
    return source.hasPrefix(prefix) ? 1 : 0
}

@_cdecl("kk_string_endsWith")
public func kk_string_endsWith(_ strRaw: Int, _ suffixRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let suffix = runtimeStringFromRawOrPanic(suffixRaw, caller: #function)
    return kk_box_bool(source.hasSuffix(suffix) ? 1 : 0)
}

@_cdecl("kk_string_contains_str")
public func kk_string_contains_str(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let other = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    if other.isEmpty {
        return kk_box_bool(1)
    }
    return kk_box_bool(source.contains(other) ? 1 : 0)
}

// STDLIB-TEXT-FN-012: CharSequence.contains(other, ignoreCase)
//
// Adds the case-insensitive overload. When `ignoreCase` is false this matches
// `kk_string_contains_str` exactly. When true, comparison is performed scalar
// by scalar using Foundation's `caseInsensitiveCompare`, mirroring how
// `kk_string_indexOf_ignoreCase` walks Unicode scalar arrays so behaviour stays
// consistent across the `contains` / `indexOf` family.
@_cdecl("kk_string_contains_ignoreCase")
public func kk_string_contains_ignoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let other = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    let ignoreCase = ignoreCaseRaw != 0

    if other.isEmpty {
        return kk_box_bool(1)
    }
    if !ignoreCase {
        return kk_box_bool(source.contains(other) ? 1 : 0)
    }

    let sourceScalars = Array(source.unicodeScalars)
    let otherScalars = Array(other.unicodeScalars)
    if otherScalars.count > sourceScalars.count {
        return kk_box_bool(0)
    }
    for offset in 0 ... (sourceScalars.count - otherScalars.count) {
        let slice = sourceScalars[offset ..< (offset + otherScalars.count)]
        let matches = zip(slice, otherScalars).allSatisfy {
            String($0).caseInsensitiveCompare(String($1)) == .orderedSame
        }
        if matches {
            return kk_box_bool(1)
        }
    }
    return kk_box_bool(0)
}

@_cdecl("kk_string_contains_ignoreCase_flat")
public func kk_string_contains_ignoreCase_flat(
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
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let other = runtimeStringFromFlatFields(data: otherData, length: otherLength, byteCount: otherByteCount, hash: otherHash)
    if other.isEmpty {
        return 1
    }
    if ignoreCaseRaw == 0 {
        return source.contains(other) ? 1 : 0
    }
    let sourceScalars = Array(source.unicodeScalars)
    let otherScalars = Array(other.unicodeScalars)
    if otherScalars.count > sourceScalars.count {
        return 0
    }
    for offset in 0 ... (sourceScalars.count - otherScalars.count) {
        let slice = sourceScalars[offset ..< (offset + otherScalars.count)]
        let matches = zip(slice, otherScalars).allSatisfy {
            String($0).caseInsensitiveCompare(String($1)) == .orderedSame
        }
        if matches {
            return 1
        }
    }
    return 0
}
// MARK: - Bridge functions for case conversion (MIGRATION-TEXT-005)

@_cdecl("__string_lowercase")
public func __string_lowercase(_ strRaw: Int) -> Int {
    return kk_string_lowercase(strRaw)
}

@_cdecl("__string_uppercase")
public func __string_uppercase(_ strRaw: Int) -> Int {
    return kk_string_uppercase(strRaw)
}

@_cdecl("__string_lowercase_locale")
public func __string_lowercase_locale(_ strRaw: Int, _ localeRaw: Int) -> Int {
    return kk_string_lowercase_locale(strRaw, localeRaw)
}

@_cdecl("__string_uppercase_locale")
public func __string_uppercase_locale(_ strRaw: Int, _ localeRaw: Int) -> Int {
    return kk_string_uppercase_locale(strRaw, localeRaw)
}
