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

@_cdecl("kk_string_uppercase_locale")
public func kk_string_uppercase_locale(_ strRaw: Int, _ localeRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        return runtimeMakeStringRaw(source.uppercased())
    }
    return runtimeMakeStringRaw(source.uppercased(with: box.locale))
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

private enum NormalizationFormTag: Int {
    case nfc = 0
    case nfd = 1
    case nfkc = 2
    case nfkd = 3
}

@_cdecl("kk_normalization_form_nfc")
public func kk_normalization_form_nfc() -> Int { NormalizationFormTag.nfc.rawValue }

@_cdecl("kk_normalization_form_nfd")
public func kk_normalization_form_nfd() -> Int { NormalizationFormTag.nfd.rawValue }

@_cdecl("kk_normalization_form_nfkc")
public func kk_normalization_form_nfkc() -> Int { NormalizationFormTag.nfkc.rawValue }

@_cdecl("kk_normalization_form_nfkd")
public func kk_normalization_form_nfkd() -> Int { NormalizationFormTag.nfkd.rawValue }

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

@_cdecl("kk_string_normalize")
public func kk_string_normalize(_ strRaw: Int, _ formTagRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(runtimeNormalizedString(source, formTagRaw: formTagRaw))
}

@_cdecl("kk_string_isNormalized")
public func kk_string_isNormalized(_ strRaw: Int, _ formTagRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
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


@_cdecl("kk_string_replace")
public func kk_string_replace(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldValue, with: newValue))
}

// MARK: - STDLIB-TEXT-FN-055: String.replace overloads

@_cdecl("kk_string_replace_char")
public func kk_string_replace_char(_ strRaw: Int, _ oldCharRaw: Int, _ newCharRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldStr = runtimeCharacterFromRaw(oldCharRaw)
    let newStr = runtimeCharacterFromRaw(newCharRaw)
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldStr, with: newStr))
}

@_cdecl("kk_string_replace_ignoreCase")
public func kk_string_replace_ignoreCase(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
    let options: String.CompareOptions = ignoreCaseRaw != 0 ? [.caseInsensitive] : []
    return runtimeMakeStringRaw(source.replacingOccurrences(of: oldValue, with: newValue, options: options))
}

@_cdecl("kk_string_replace_char_ignoreCase")
public func kk_string_replace_char_ignoreCase(_ strRaw: Int, _ oldCharRaw: Int, _ newCharRaw: Int, _ ignoreCaseRaw: Int) -> Int {
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
            message:
            "StringIndexOutOfBoundsException: start=\(start), end=\(hasEnd ? end : length), length=\(length)"
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
            message: "IndexOutOfBoundsException: startIndex=\(startIndex), endIndex=\(endIndex), length=\(units.count)"
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

@_cdecl("kk_string_codePointCount")
public func kk_string_codePointCount(_ strRaw: Int) -> Int {
    let units = runtimeStringUTF16CodeUnits(strRaw)
    return runtimeStringCodePointCount(units: units, startIndex: 0, endIndex: units.count, outThrown: nil)
}

@_cdecl("kk_string_codePointCount_from")
public func kk_string_codePointCount_from(
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

@_cdecl("kk_string_codePointCount_range")
public func kk_string_codePointCount_range(
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
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    return runtimeMakeListRaw(charRaws)
}

// MARK: - STDLIB-TEXT-FN-104: CharSequence.toMutableList() — MutableList<Char>

/// Converts a `String` to a fresh `MutableList<Char>` by iterating its Unicode
/// scalars.  In the runtime, `List` and `MutableList` share the same
/// `RuntimeListBox` representation, so this mirrors `kk_string_toList` while
/// returning a value the caller can mutate.
/// Implements `kotlin.text.CharSequence.toMutableList(): MutableList<Char>`.
@_cdecl("kk_string_toMutableList")
public func kk_string_toMutableList(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    return runtimeMakeListRaw(charRaws)
}

@_cdecl("kk_string_toCharArray")
public func kk_string_toCharArray(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    return runtimeMakeArrayRaw(charRaws)
}

// MARK: - STDLIB-TEXT-FN-109: String.toTypedArray() — Array<Char>

/// Converts a `String` to a boxed `Array<Char>` by iterating its Unicode scalars.
/// Unlike `toCharArray()` which returns a primitive `CharArray`, this returns a
/// generic `Array<Char>` compatible with `Collection<Char>.toTypedArray()`.
@_cdecl("kk_string_toTypedArray")
public func kk_string_toTypedArray(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    return runtimeMakeArrayRaw(charRaws)
}

// MARK: - STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)

/// Appends every character of the string (as a boxed `Char`) to `destRaw`,
/// which must be a mutable collection (List or Set).  Returns `destRaw` so
/// callers can chain: `val result = "abc".toCollection(mutableListOf())`.
///
/// Mirrors `kotlin.text.CharSequence.toCollection<C : MutableCollection<in Char>>`.
@_cdecl("kk_string_toCollection")
public func kk_string_toCollection(_ strRaw: Int, _ destRaw: Int) -> Int {
    let charRaws = runtimeStringScalars(strRaw).map { kk_box_char(Int($0.value)) }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for charRaw in charRaws {
        runtimeAppendToMutableCollection(destRaw, charRaw)
    }
    return destRaw
}

// MARK: - STDLIB-TEXT-FN-108: CharSequence.toSortedSet()

/// Returns a `SortedSet<Char>` containing all unique UTF-16 code units of the string
/// in their natural `Char` ascending order.
/// Implements `kotlin.text.CharSequence.toSortedSet(): SortedSet<Char>`.
@_cdecl("kk_string_toSortedSet")
public func kk_string_toSortedSet(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringUTF16CodeUnits(strRaw).map { kk_box_char(Int($0)) }
    let deduped = runtimeDeduplicatePreservingOrder(charRaws)
    let sorted = deduped.sorted { runtimeCompareValues($0, $1) < 0 }
    return registerRuntimeObject(RuntimeSetBox(elements: sorted))
}

// MARK: - STDLIB-640: CharArray.concatToString()

/// Converts a `CharArray` to a `String` by concatenating all characters.
/// This is the inverse of `String.toCharArray()`.
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
@_cdecl("kk_string_asIterable")
public func kk_string_asIterable(_ strRaw: Int) -> Int {
    let box = RuntimeStringIterableBox(strRaw: strRaw)
    return registerRuntimeObject(box)
}

/// Materialise the lazy string-iterable into a `List<Char>`.
/// Called when `toList()` is invoked on the iterable returned by `asIterable()`,
/// or when the for-in lowering needs a concrete list.
@_cdecl("kk_string_iterable_toList")
public func kk_string_iterable_toList(_ iterableRaw: Int) -> Int {
    guard let box = runtimeStringIterableBox(from: iterableRaw) else {
        // Validate that the raw value is a valid string handle before falling
        // back, to avoid reinterpreting an unrelated object pointer as a string.
        if extractString(from: UnsafeMutableRawPointer(bitPattern: iterableRaw)) != nil {
            return kk_string_toList(iterableRaw)
        }
        // Unrecognised input — return an empty list.
        return kk_string_toList(runtimeMakeStringRaw(""))
    }
    return kk_string_toList(box.strRaw)
}

/// Create an iterator from a lazy string iterable (for `for (c in str.asIterable())`).
@_cdecl("kk_string_iterable_iterator")
public func kk_string_iterable_iterator(_ iterableRaw: Int) -> Int {
    if let box = runtimeStringIterableBox(from: iterableRaw) {
        return kk_string_iterator(box.strRaw)
    }
    // Validate that the raw value is a valid string handle before falling
    // back, to avoid reinterpreting an unrelated object pointer as a string.
    if extractString(from: UnsafeMutableRawPointer(bitPattern: iterableRaw)) != nil {
        return kk_string_iterator(iterableRaw)
    }
    // Return an empty iterator for unrecognised inputs (including null
    // sentinel) rather than misinterpreting them as string handles.
    let box = RuntimeStringIteratorBox(charRaws: [])
    return registerRuntimeObject(box)
}

@_cdecl("kk_string_asSequence")
public func kk_string_asSequence(_ strRaw: Int) -> Int {
    // Lazy: store only the string handle; characters are yielded on demand
    let seq = RuntimeSequenceBox(steps: [.stringSource(strRaw: strRaw)])
    return registerRuntimeObject(seq)
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
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
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

@_cdecl("kk_string_takeLast")
public func kk_string_takeLast(_ strRaw: Int, _ nRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if nRaw < 0 {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
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
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
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
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: Requested element count \(nRaw) is less than zero.")
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
// MARK: - Bridge functions for replace operations (MIGRATION-TEXT-005)

@_cdecl("__string_replace")
public func __string_replace(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    return kk_string_replace(strRaw, oldRaw, newRaw)
}

@_cdecl("__string_replace_ignoreCase")
public func __string_replace_ignoreCase(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    return kk_string_replace_ignoreCase(strRaw, oldRaw, newRaw, ignoreCaseRaw)
}

@_cdecl("__string_replace_char")
public func __string_replace_char(_ strRaw: Int, _ oldCharRaw: Int, _ newCharRaw: Int) -> Int {
    return kk_string_replace_char(strRaw, oldCharRaw, newCharRaw)
}

@_cdecl("__string_replace_char_ignoreCase")
public func __string_replace_char_ignoreCase(_ strRaw: Int, _ oldCharRaw: Int, _ newCharRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    return kk_string_replace_char_ignoreCase(strRaw, oldCharRaw, newCharRaw, ignoreCaseRaw)
}

@_cdecl("__string_removePrefix")
public func __string_removePrefix(_ strRaw: Int, _ prefixRaw: Int) -> Int {
    return kk_string_removePrefix(strRaw, prefixRaw)
}

@_cdecl("__string_removeSuffix")
public func __string_removeSuffix(_ strRaw: Int, _ suffixRaw: Int) -> Int {
    return kk_string_removeSuffix(strRaw, suffixRaw)
}

@_cdecl("__string_removeSurrounding")
public func __string_removeSurrounding(_ strRaw: Int, _ delimiterRaw: Int) -> Int {
    return kk_string_removeSurrounding(strRaw, delimiterRaw)
}

@_cdecl("__string_removeSurrounding_pair")
public func __string_removeSurrounding_pair(_ strRaw: Int, _ prefixRaw: Int, _ suffixRaw: Int) -> Int {
    return kk_string_removeSurrounding_pair(strRaw, prefixRaw, suffixRaw)
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
