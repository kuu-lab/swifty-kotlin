// Substring extraction and replacement functions (substringBefore/After,
// replaceAfter/Before, replaceFirst, replaceRange, removeRange).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

// MARK: - Private helpers

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
    let idx = kk_string_indexOf(strRaw, delimiterRaw)
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
    let idx = kk_string_lastIndexOf(strRaw, delimiterRaw)
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
    let idx = kk_string_lastIndexOf(strRaw, delimiterRaw)
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

@_cdecl("kk_string_replaceFirst")
public func kk_string_replaceFirst(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
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

@_cdecl("kk_string_replaceRange")
public func kk_string_replaceRange(
    _ strRaw: Int,
    _ rangeRaw: Int,
    _ replacementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, message: "Invalid range for replaceRange")
        return 0
    }
    let first = range.first
    let last = range.last
    let length = scalars.count
    if first < 0 || first > length || last < -1 || last >= length || first > last + 1 {
        runtimeSetThrown(
            outThrown,
            message: "StringIndexOutOfBoundsException: start=\(first), end=\(last + 1), length=\(length)"
        )
        return 0
    }
    let endIndex = last + 1
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let before = runtimeStringFromScalars(scalars[0 ..< first])
    let after = runtimeStringFromScalars(scalars[endIndex...])
    return runtimeMakeStringRaw(before + replacement + after)
}

// MARK: - STDLIB-TEXT-EDGE-008: removeRange

@_cdecl("kk_string_removeRange")
public func kk_string_removeRange(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    let length = scalars.count
    let start = startRaw
    let end = endRaw
    if start < 0 || start > length || end < 0 || end > length || start > end {
        runtimeSetThrown(
            outThrown,
            message: "StringIndexOutOfBoundsException: start=\(start), end=\(end), length=\(length)"
        )
        return 0
    }
    let before = runtimeStringFromScalars(scalars[0 ..< start])
    let after = runtimeStringFromScalars(scalars[end...])
    return runtimeMakeStringRaw(before + after)
}

@_cdecl("kk_string_removeRange_range")
public func kk_string_removeRange_range(
    _ strRaw: Int,
    _ rangeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, message: "Invalid range for removeRange")
        return 0
    }
    return kk_string_removeRange(strRaw, range.first, range.last + 1, outThrown)
}

// MARK: - Bridge functions for substring/replace/remove operations (MIGRATION-TEXT-005)

@_cdecl("__string_replaceFirst")
public func __string_replaceFirst(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    return kk_string_replaceFirst(strRaw, oldRaw, newRaw)
}

@_cdecl("__string_replaceRange")
public func __string_replaceRange(_ strRaw: Int, _ rangeRaw: Int, _ replacementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return kk_string_replaceRange(strRaw, rangeRaw, replacementRaw, outThrown)
}

@_cdecl("__string_removeRange")
public func __string_removeRange(_ strRaw: Int, _ startRaw: Int, _ endRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return kk_string_removeRange(strRaw, startRaw, endRaw, outThrown)
}

@_cdecl("__string_removeRange_range")
public func __string_removeRange_range(_ strRaw: Int, _ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return kk_string_removeRange_range(strRaw, rangeRaw, outThrown)
}
