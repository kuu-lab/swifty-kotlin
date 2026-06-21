// String search / index functions (indexOf, lastIndexOf, findAnyOf,
// indexOfFirst, indexOfLast, and their ignoreCase / Char variants).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

@_cdecl("kk_string_indexOf")
public func kk_string_indexOf(_ strRaw: Int, _ otherRaw: Int) -> Int {
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

// MARK: - String.indexOf(String, startIndex) / indexOfFirst / indexOfLast

@_cdecl("kk_string_indexOf_from")
public func kk_string_indexOf_from(_ strRaw: Int, _ otherRaw: Int, _ startIndex: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    let other = runtimeStringScalars(otherRaw)

    let start = max(0, min(startIndex, source.count))
    if other.isEmpty {
        return start
    }
    if other.count > source.count - start {
        return -1
    }

    for offset in start ... (source.count - other.count)
        where source[offset ..< (offset + other.count)].elementsEqual(other)
    {
        return offset
    }
    return -1
}

@_cdecl("kk_string_indexOfAny_chars")
public func kk_string_indexOfAny_chars(_ strRaw: Int, _ charsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let chars = runtimeArrayBox(from: charsRaw), !source.isEmpty, !chars.elements.isEmpty else {
        return -1
    }
    let start = max(0, startIndex)
    guard start < source.count else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    let needles = chars.elements.compactMap { UnicodeScalar(kk_unbox_char($0)) }
    guard !needles.isEmpty else {
        return -1
    }
    for offset in start..<source.count {
        let scalar = source[offset]
        if needles.contains(where: { needle in
            if !ignoreCase { return scalar == needle }
            return String(scalar).caseInsensitiveCompare(String(needle)) == .orderedSame
        }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_indexOfAny_strings")
public func kk_string_indexOfAny_strings(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return -1
    }
    let needles = elements.map { runtimeStringScalars($0) }
    let clampedStart = max(0, min(startIndex, source.count))
    if needles.contains(where: \.isEmpty) {
        return clampedStart
    }
    let start = max(0, startIndex)
    guard start < source.count else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in start..<source.count {
        // swiftlint:disable:next for_where
        if needles.contains(where: { matches($0, at: offset) }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_lastIndexOfAny_chars")
public func kk_string_lastIndexOfAny_chars(_ strRaw: Int, _ charsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let chars = runtimeArrayBox(from: charsRaw), !source.isEmpty, !chars.elements.isEmpty else {
        return -1
    }
    let start = min(startIndex, source.count - 1)
    guard start >= 0 else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    let needles = chars.elements.compactMap { UnicodeScalar(kk_unbox_char($0)) }
    guard !needles.isEmpty else {
        return -1
    }
    for offset in stride(from: start, through: 0, by: -1) {
        let scalar = source[offset]
        if needles.contains(where: { needle in
            if !ignoreCase { return scalar == needle }
            return String(scalar).caseInsensitiveCompare(String(needle)) == .orderedSame
        }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_lastIndexOfAny_strings")
public func kk_string_lastIndexOfAny_strings(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return -1
    }
    let needles = elements.map { runtimeStringScalars($0) }
    let clampedStart = min(startIndex, source.count)
    if needles.contains(where: \.isEmpty) {
        return clampedStart >= 0 ? clampedStart : -1
    }
    guard !source.isEmpty else {
        return -1
    }
    let start = min(startIndex, source.count - 1)
    guard start >= 0 else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in stride(from: start, through: 0, by: -1) {
        // swiftlint:disable:next for_where
        if needles.contains(where: { matches($0, at: offset) }) {
            return offset
        }
    }
    return -1
}

@_cdecl("kk_string_findAnyOf")
public func kk_string_findAnyOf(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    let needles = elements.map { (raw: $0, scalars: runtimeStringScalars($0)) }
    let clampedStart = max(0, min(startIndex, source.count))
    if let emptyNeedle = needles.first(where: { $0.scalars.isEmpty }) {
        return kk_pair_new(clampedStart, emptyNeedle.raw)
    }
    let start = max(0, startIndex)
    guard start < source.count else {
        return runtimeNullSentinelInt
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in start..<source.count {
        for needle in needles where matches(needle.scalars, at: offset) {
            return kk_pair_new(offset, needle.raw)
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_findLastAnyOf")
public func kk_string_findLastAnyOf(_ strRaw: Int, _ stringsRaw: Int, _ startIndex: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let elements = runtimeCollectionElements(from: stringsRaw) ?? runtimeArrayBox(from: stringsRaw)?.elements,
          !elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    let needles = elements.map { (raw: $0, scalars: runtimeStringScalars($0)) }
    let clampedStart = min(startIndex, source.count)
    if let emptyNeedle = needles.first(where: { $0.scalars.isEmpty }) {
        return clampedStart >= 0 ? kk_pair_new(clampedStart, emptyNeedle.raw) : runtimeNullSentinelInt
    }
    guard !source.isEmpty else {
        return runtimeNullSentinelInt
    }
    let start = min(startIndex, source.count - 1)
    guard start >= 0 else {
        return runtimeNullSentinelInt
    }
    let ignoreCase = ignoreCaseRaw != 0
    func matches(_ needle: [UnicodeScalar], at offset: Int) -> Bool {
        guard offset + needle.count <= source.count else {
            return false
        }
        let haystackSlice = source[offset ..< offset + needle.count]
        if !ignoreCase {
            return haystackSlice.elementsEqual(needle)
        }
        return zip(haystackSlice, needle).allSatisfy { lhs, rhs in
            String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
        }
    }
    for offset in stride(from: start, through: 0, by: -1) {
        for needle in needles where matches(needle.scalars, at: offset) {
            return kk_pair_new(offset, needle.raw)
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_indexOfFirst")
public func kk_string_indexOfFirst(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (index, scalar) in scalars.enumerated() {
        let charRaw = Int(scalar.value)
        var thrown = 0
        let result = lambda(closureRaw, charRaw, &thrown)
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: "indexOfFirst predicate")
            return -1
        }
        if maybeUnbox(result) != 0 {
            return index
        }
    }
    return -1
}

@_cdecl("kk_string_indexOfLast")
public func kk_string_indexOfLast(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var lastIndex = -1
    for (index, scalar) in scalars.enumerated() {
        let charRaw = Int(scalar.value)
        var thrown = 0
        let result = lambda(closureRaw, charRaw, &thrown)
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: "indexOfLast predicate")
            return -1
        }
        if maybeUnbox(result) != 0 {
            lastIndex = index
        }
    }
    return lastIndex
}

@_cdecl("kk_string_lastIndexOf")
public func kk_string_lastIndexOf(_ strRaw: Int, _ otherRaw: Int) -> Int {
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

// MARK: - STDLIB-TEXT-FN-020: CharSequence.indexOf(Char, startIndex, ignoreCase)

@_cdecl("kk_string_indexOf_char")
public func kk_string_indexOf_char(_ strRaw: Int, _ charRaw: Int, _ startIndexRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let needle = UnicodeScalar(kk_unbox_char(charRaw)) else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    let start = max(0, startIndexRaw)
    guard start < source.count else {
        return -1
    }
    let needleString = String(needle)
    for offset in start..<source.count {
        let scalar = source[offset]
        if ignoreCase {
            if String(scalar).caseInsensitiveCompare(needleString) == .orderedSame {
                return offset
            }
        } else if scalar == needle {
            return offset
        }
    }
    return -1
}

// MARK: - STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase

@_cdecl("kk_string_indexOf_ignoreCase")
public func kk_string_indexOf_ignoreCase(_ strRaw: Int, _ otherRaw: Int, _ startIndexRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let other = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    let ignoreCase = ignoreCaseRaw != 0

    if other.isEmpty {
        let start = max(0, min(startIndexRaw, source.unicodeScalars.count))
        return start
    }

    let sourceScalars = Array(source.unicodeScalars)
    let otherScalars = Array(other.unicodeScalars)
    let start = max(0, min(startIndexRaw, sourceScalars.count))

    if otherScalars.count > sourceScalars.count - start {
        return -1
    }

    for offset in start ... (sourceScalars.count - otherScalars.count) {
        let slice = sourceScalars[offset ..< (offset + otherScalars.count)]
        let matches: Bool
        if ignoreCase {
            matches = zip(slice, otherScalars).allSatisfy {
                String($0).caseInsensitiveCompare(String($1)) == .orderedSame
            }
        } else {
            matches = slice.elementsEqual(otherScalars)
        }
        if matches { return offset }
    }
    return -1
}

@_cdecl("kk_string_lastIndexOf_ignoreCase")
public func kk_string_lastIndexOf_ignoreCase(_ strRaw: Int, _ otherRaw: Int, _ startIndexRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let other = runtimeStringFromRawOrPanic(otherRaw, caller: #function)
    let ignoreCase = ignoreCaseRaw != 0

    let sourceScalars = Array(source.unicodeScalars)
    let otherScalars = Array(other.unicodeScalars)

    if other.isEmpty {
        let start = max(0, min(startIndexRaw, sourceScalars.count))
        return start
    }
    if otherScalars.count > sourceScalars.count {
        return -1
    }

    let maxOffset = sourceScalars.count - otherScalars.count
    let start = max(0, min(startIndexRaw, maxOffset))

    var lastIndex = -1
    for offset in 0 ... start {
        let slice = sourceScalars[offset ..< (offset + otherScalars.count)]
        let matches: Bool
        if ignoreCase {
            matches = zip(slice, otherScalars).allSatisfy {
                String($0).caseInsensitiveCompare(String($1)) == .orderedSame
            }
        } else {
            matches = slice.elementsEqual(otherScalars)
        }
        if matches { lastIndex = offset }
    }
    return lastIndex
}

// MARK: - STDLIB-TEXT-FN-034: CharSequence.lastIndexOf(Char, startIndex, ignoreCase)

@_cdecl("kk_string_lastIndexOf_char")
public func kk_string_lastIndexOf_char(_ strRaw: Int, _ charRaw: Int, _ startIndexRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    let source = runtimeStringScalars(strRaw)
    guard let needle = runtimeUnicodeScalarFromRaw(charRaw) else {
        return -1
    }
    guard !source.isEmpty else {
        return -1
    }
    let ignoreCase = ignoreCaseRaw != 0
    let start = min(startIndexRaw, source.count - 1)
    guard start >= 0 else {
        return -1
    }
    let needleStr = String(needle)
    for offset in stride(from: start, through: 0, by: -1) {
        let scalar = source[offset]
        if ignoreCase {
            if String(scalar).caseInsensitiveCompare(needleStr) == .orderedSame {
                return offset
            }
        } else if scalar == needle {
            return offset
        }
    }
    return -1
}
