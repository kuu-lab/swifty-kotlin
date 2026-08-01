// Substring extraction and replacement functions (substringBefore/After,
// replaceAfter/Before, replaceFirst, replaceRange, removeRange).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

// MARK: - Private helpers

// KSP-408 moved the public `kk_string_indexOf`/`kk_string_lastIndexOf` entry points to
// bundled Kotlin source. substringBefore/substringBeforeLast/substringAfterLast (not yet
// migrated) still need scalar-index substring search internally, so this file keeps a
// private copy of the same algorithm rather than depending on removed Kotlin-facing ABI.
private func runtimeStringIndexOfScalar(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    let other = runtimeStringScalars(otherRaw)
    if other.isEmpty {
        return 0
    }
    if other.count > source.count {
        return -1
    }
    for offset in 0 ... (source.count - other.count)
        where source[offset ..< (offset + other.count)].elementsEqual(other)
    {
        return offset
    }
    return -1
}

private func runtimeStringLastIndexOfScalar(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    let other = runtimeStringScalars(otherRaw)
    if other.isEmpty {
        return source.count
    }
    if other.count > source.count {
        return -1
    }
    var lastIndex = -1
    for offset in 0 ... (source.count - other.count)
        where source[offset ..< (offset + other.count)].elementsEqual(other)
    {
        lastIndex = offset
    }
    return lastIndex
}

private func runtimeStringSubstringAfter(
    source: String,
    delimiter: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        return source
    }
    guard let range = source.range(of: delimiter) else {
        return missingDelimiterValue
    }
    return String(source[range.upperBound...])
}

private func runtimeStringReplaceAfter(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        return replacement
    }
    guard let range = source.range(of: delimiter) else {
        return missingDelimiterValue
    }
    return String(source[..<range.upperBound]) + replacement
}

private func runtimeStringReplaceAfterLast(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        guard !source.isEmpty else {
            return missingDelimiterValue
        }
        return runtimeStringFromScalars(source.unicodeScalars.dropLast()) + replacement
    }
    guard let range = source.range(of: delimiter, options: .backwards) else {
        return missingDelimiterValue
    }
    return String(source[..<range.upperBound]) + replacement
}

private func runtimeStringReplaceBefore(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        return replacement + source
    }
    guard let range = source.range(of: delimiter) else {
        return missingDelimiterValue
    }
    return replacement + String(source[range.lowerBound...])
}

private func runtimeStringReplaceBeforeLast(
    source: String,
    delimiter: String,
    replacement: String,
    missingDelimiterValue: String
) -> String {
    if delimiter.isEmpty {
        guard let lastScalar = source.unicodeScalars.last else {
            return missingDelimiterValue
        }
        return replacement + String(lastScalar)
    }
    guard let range = source.range(of: delimiter, options: .backwards) else {
        return missingDelimiterValue
    }
    return replacement + String(source[range.lowerBound...])
}

@inline(__always)
private func runtimeSubstringMissingDelimiterValue(
    sourceRaw: Int,
    source: String,
    missingDelimiterValueRaw: Int,
    caller: StaticString
) -> String {
    if missingDelimiterValueRaw == 0 || missingDelimiterValueRaw == sourceRaw {
        return source
    }
    return runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: caller)
}

// MARK: - STDLIB-186: substringBefore / substringAfter / substringBeforeLast / substringAfterLast
//
// STDLIB-TEXT-FN-076: `String.substringBefore(delimiter, missingDelimiterValue)` is the
// public Kotlin signature. We expose four runtime helpers per direction (before/after
// and before-last/after-last), one for `String` delimiters and one for `Char`. Each
// accepts an optional `missingDelimiterValueRaw` boxed string; passing `0` means the
// Kotlin default (`this`) should be returned when no match is found.

@_cdecl("kk_string_substringBefore")
public func kk_string_substringBefore(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let idx = runtimeStringIndexOfScalar(strRaw, delimiterRaw)
    if idx < 0 {
        return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
            sourceRaw: strRaw,
            source: source,
            missingDelimiterValueRaw: missingDelimiterValueRaw,
            caller: #function
        ))
    }
    let scalars = runtimeStringScalars(strRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
}

@_cdecl("kk_string_substringBefore_char")
public func kk_string_substringBefore_char(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let scalars = runtimeStringScalars(strRaw)
    if let idx = scalars.firstIndex(where: { UnicodeScalar($0) == UnicodeScalar(delimiter) }) {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
    }
    return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
        sourceRaw: strRaw,
        source: source,
        missingDelimiterValueRaw: missingDelimiterValueRaw,
        caller: #function
    ))
}

@_cdecl("kk_string_substringAfter")
public func kk_string_substringAfter(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringSubstringAfter(
            source: source,
            delimiter: delimiter,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_substringAfter_char")
public func kk_string_substringAfter_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringSubstringAfter(
            source: source,
            delimiter: delimiter,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_substringBeforeLast")
public func kk_string_substringBeforeLast(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let idx = runtimeStringLastIndexOfScalar(strRaw, delimiterRaw)
    if idx < 0 {
        return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
            sourceRaw: strRaw,
            source: source,
            missingDelimiterValueRaw: missingDelimiterValueRaw,
            caller: #function
        ))
    }
    let scalars = runtimeStringScalars(strRaw)
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
}

@_cdecl("kk_string_substringBeforeLast_char")
public func kk_string_substringBeforeLast_char(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let scalars = runtimeStringScalars(strRaw)
    if let idx = scalars.lastIndex(where: { UnicodeScalar($0) == UnicodeScalar(delimiter) }) {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[0 ..< idx]))
    }
    return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
        sourceRaw: strRaw,
        source: source,
        missingDelimiterValueRaw: missingDelimiterValueRaw,
        caller: #function
    ))
}

@_cdecl("kk_string_substringAfterLast")
public func kk_string_substringAfterLast(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let idx = runtimeStringLastIndexOfScalar(strRaw, delimiterRaw)
    if idx < 0 {
        return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
            sourceRaw: strRaw,
            source: source,
            missingDelimiterValueRaw: missingDelimiterValueRaw,
            caller: #function
        ))
    }
    let scalars = runtimeStringScalars(strRaw)
    let delimScalars = runtimeStringScalars(delimiterRaw)
    let start = idx + delimScalars.count
    return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[start...]))
}

@_cdecl("kk_string_substringAfterLast_char")
public func kk_string_substringAfterLast_char(_ strRaw: Int, _ delimiterRaw: Int, _ missingDelimiterValueRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let scalars = runtimeStringScalars(strRaw)
    if let idx = scalars.lastIndex(where: { UnicodeScalar($0) == UnicodeScalar(delimiter) }) {
        return runtimeMakeStringRaw(runtimeStringFromScalars(scalars[(idx + 1)...]))
    }
    return runtimeMakeStringRaw(runtimeSubstringMissingDelimiterValue(
        sourceRaw: strRaw,
        source: source,
        missingDelimiterValueRaw: missingDelimiterValueRaw,
        caller: #function
    ))
}

@_cdecl("kk_string_replaceAfter")
public func kk_string_replaceAfter(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfter(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceAfter_char")
public func kk_string_replaceAfter_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfter(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceAfterLast")
public func kk_string_replaceAfterLast(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfterLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceAfterLast_char")
public func kk_string_replaceAfterLast_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceAfterLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBefore")
public func kk_string_replaceBefore(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBefore(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBefore_char")
public func kk_string_replaceBefore_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBefore(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBeforeLast")
public func kk_string_replaceBeforeLast(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimiterRaw, caller: #function)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBeforeLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

@_cdecl("kk_string_replaceBeforeLast_char")
public func kk_string_replaceBeforeLast_char(
    _ strRaw: Int,
    _ delimiterRaw: Int,
    _ replacementRaw: Int,
    _ missingDelimiterValueRaw: Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeCharacterFromRaw(delimiterRaw)
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let missingDelimiterValue = missingDelimiterValueRaw == 0
        ? source
        : runtimeStringFromRawOrPanic(missingDelimiterValueRaw, caller: #function)
    return runtimeMakeStringRaw(
        runtimeStringReplaceBeforeLast(
            source: source,
            delimiter: delimiter,
            replacement: replacement,
            missingDelimiterValue: missingDelimiterValue
        )
    )
}

// MARK: - STDLIB-188: replaceFirst / replaceRange

func runtimeStringReplaceFirst(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
    guard let range = source.range(of: oldValue) else {
        return runtimeMakeStringRaw(source)
    }
    var result = source
    result.replaceSubrange(range, with: newValue)
    return runtimeMakeStringRaw(result)
}

// KSP-406: replaceRange / removeRange are bundled Kotlin source
// (Stdlib/kotlin/text/StringSubstringSlice.kt); no runtime ABI remains.

// MARK: - Flat ABI wrappers

@_cdecl("kk_string_substringBefore_flat")
public func kk_string_substringBefore_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringBefore(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_substringBefore_char_flat")
public func kk_string_substringBefore_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringBefore_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_substringBeforeLast_flat")
public func kk_string_substringBeforeLast_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringBeforeLast(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_substringBeforeLast_char_flat")
public func kk_string_substringBeforeLast_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringBeforeLast_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_substringAfter_flat")
public func kk_string_substringAfter_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringAfter(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_substringAfter_char_flat")
public func kk_string_substringAfter_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringAfter_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_substringAfterLast_flat")
public func kk_string_substringAfterLast_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringAfterLast(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_substringAfterLast_char_flat")
public func kk_string_substringAfterLast_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_substringAfterLast_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceAfter_flat")
public func kk_string_replaceAfter_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceAfter(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceAfter_char_flat")
public func kk_string_replaceAfter_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceAfter_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceAfterLast_flat")
public func kk_string_replaceAfterLast_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceAfterLast(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceAfterLast_char_flat")
public func kk_string_replaceAfterLast_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceAfterLast_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceBefore_flat")
public func kk_string_replaceBefore_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceBefore(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceBefore_char_flat")
public func kk_string_replaceBefore_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceBefore_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceBeforeLast_flat")
public func kk_string_replaceBeforeLast_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterData: UnsafePointer<UInt8>?, _ delimiterLength: Int, _ delimiterByteCount: Int, _ delimiterHash: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceBeforeLast(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimiterData, delimiterLength, delimiterByteCount, delimiterHash),
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceBeforeLast_char_flat")
public func kk_string_replaceBeforeLast_char_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ delimiterRaw: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ missingData: UnsafePointer<UInt8>?, _ missingLength: Int, _ missingByteCount: Int, _ missingHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceBeforeLast_char(
        kk_string_from_flat(data, length, byteCount, hash),
        delimiterRaw,
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        kk_string_from_flat(missingData, missingLength, missingByteCount, missingHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceFirst_flat")
public func kk_string_replaceFirst_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ oldData: UnsafePointer<UInt8>?, _ oldLength: Int, _ oldByteCount: Int, _ oldHash: Int,
    _ newData: UnsafePointer<UInt8>?, _ newLength: Int, _ newByteCount: Int, _ newHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = runtimeStringReplaceFirst(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(oldData, oldLength, oldByteCount, oldHash),
        kk_string_from_flat(newData, newLength, newByteCount, newHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

// KSP-406: removeRange / replaceRange flat wrappers removed with the bundled
// Kotlin source migration (Stdlib/kotlin/text/StringSubstringSlice.kt).
