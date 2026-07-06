// Shared helper functions for RuntimeStringStdlib and its split-out files.
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

func runtimeNormalizedMultilineString(_ source: String) -> [String] {
    source
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}

func runtimeStringScalars(_ raw: Int) -> [UnicodeScalar] {
    Array(runtimeStringFromRawOrPanic(raw, caller: #function).unicodeScalars)
}

func runtimeStringUTF16CodeUnits(_ raw: Int) -> [UInt16] {
    Array(runtimeStringFromRawOrPanic(raw, caller: #function).utf16)
}

func runtimeStringFromScalars(_ scalars: some Sequence<UnicodeScalar>) -> String {
    String(String.UnicodeScalarView(scalars))
}

func runtimeStringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: pointer)
}

/// Fail-fast variant that panics on invalid string handles instead of returning nil.
/// Use this instead of `runtimeStringFromRaw(...) ?? ""` to distinguish
/// invalid handles from legitimately empty strings.
/// Internal so that other runtime files (e.g. RuntimeSequence.swift) can share
/// this helper without duplicating the safety check and panic message.
func runtimeStringFromRawOrPanic(_ raw: Int, caller: StaticString) -> String {
    if let s = runtimeStringFromRaw(raw) {
        return s
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
}

func runtimeCharacterFromRaw(_ raw: Int) -> String {
    guard let scalar = runtimeUnicodeScalarFromRaw(raw) else {
        return "?"
    }
    return String(scalar)
}

func runtimeUnicodeScalarFromRaw(_ raw: Int) -> UnicodeScalar? {
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw),
       runtimeIsObjectPointer(pointer),
       let charBox = tryCast(pointer, to: RuntimeCharBox.self)
    {
        return UnicodeScalar(charBox.value)
    }
    return UnicodeScalar(UInt32(truncatingIfNeeded: raw))
}

func runtimeIsObjectPointer(_ pointer: UnsafeMutableRawPointer) -> Bool {
    runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
}

func runtimeMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

func runtimeMakeListRaw(_ values: [Int]) -> Int {
    let box = RuntimeListBox(elements: values)
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: pointer))
    }
    return Int(bitPattern: pointer)
}

func runtimeMakeArrayRaw(_ values: [Int]) -> Int {
    let box = RuntimeArrayBox(length: values.count)
    for (index, value) in values.enumerated() {
        box.elements[index] = value
    }
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: pointer))
    }
    return Int(bitPattern: pointer)
}

func runtimeMakeStringListRaw(_ values: [String]) -> Int {
    runtimeMakeListRaw(values.map(runtimeMakeStringRaw))
}

func runtimePropagateThrownOrTrap(
    _ thrown: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    context: String
) {
    guard thrown != 0 else { return }
    guard let outThrown else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(context) threw")
    }
    outThrown.pointee = thrown
}

// MARK: - Raw string helpers for RuntimeCollectionHOF

func runtimeStringToCharListRaw(_ source: String) -> Int {
    runtimeMakeListRaw(source.utf16.map { Int($0) })
}

func runtimeStringIndexOfRaw(_ strRaw: Int, _ otherRaw: Int) -> Int {
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

func runtimeStringLastIndexOfRaw(_ strRaw: Int, _ otherRaw: Int) -> Int {
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

func runtimeStringIndexOfFirstFromRaw(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringIndexOfFirst(
        scalars: runtimeStringScalars(strRaw),
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown
    )
}

func runtimeStringIndexOfLastFromRaw(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringIndexOfLast(
        scalars: runtimeStringScalars(strRaw),
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown
    )
}

private func runtimeStringIndexOfFirst(
    scalars: [UnicodeScalar],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
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

private func runtimeStringIndexOfLast(
    scalars: [UnicodeScalar],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var lastIdx = -1
    for (index, scalar) in scalars.enumerated() {
        let charRaw = Int(scalar.value)
        var thrown = 0
        let result = lambda(closureRaw, charRaw, &thrown)
        if thrown != 0 {
            runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: "indexOfLast predicate")
            return -1
        }
        if maybeUnbox(result) != 0 {
            lastIdx = index
        }
    }
    return lastIdx
}

func runtimeSplitString(_ source: String, delimiter: String, limit: Int = 0) -> [String] {
    if source.isEmpty {
        return [""]
    }

    var result: [String] = []
    var cursor = source.startIndex
    while true {
        if limit > 0 && result.count == limit - 1 {
            result.append(String(source[cursor...]))
            return result
        }
        guard let match = source.range(of: delimiter, range: cursor ..< source.endIndex) else {
            result.append(String(source[cursor...]))
            return result
        }
        result.append(String(source[cursor ..< match.lowerBound]))
        cursor = match.upperBound
    }
}

func runtimeSplitStringLimit(
    _ source: String,
    delimiter: String,
    ignoreCase: Bool,
    limit: Int
) -> [String] {
    if source.isEmpty {
        return [""]
    }

    let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []
    var result: [String] = []
    var cursor = source.startIndex
    while true {
        if limit > 0, result.count == limit - 1 {
            result.append(String(source[cursor...]))
            return result
        }
        guard let match = source.range(of: delimiter, options: options, range: cursor ..< source.endIndex) else {
            result.append(String(source[cursor...]))
            return result
        }
        result.append(String(source[cursor ..< match.lowerBound]))
        cursor = match.upperBound
    }
}
