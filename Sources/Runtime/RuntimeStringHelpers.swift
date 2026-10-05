// Shared helper functions for RuntimeStringStdlib and its split-out files.
// Split out from `RuntimeStringStdlib.swift`.

import Foundation
import RuntimeABI

func runtimeStringUTF16CodeUnits(_ raw: Int) -> [UInt16] {
    if let box = runtimeStringBox(fromRaw: raw) {
        return box.utf16CodeUnits
    }
    return runtimeKotlinStringUTF16CodeUnits(runtimeStringFromRawOrPanic(raw, caller: #function))
}

/// Returns Kotlin's UTF-16 code units while decoding the compiler's isolated
/// surrogate markers back to their original values.
func runtimeKotlinStringUTF16CodeUnits(_ value: String) -> [UInt16] {
    KotlinStringSurrogateEncoding.utf16CodeUnits(value)
}

/// Appends `value`'s Kotlin UTF-16 code units to `units` without building an
/// intermediate array.
func runtimeAppendKotlinUTF16CodeUnits(of value: String, to units: inout [UInt16]) {
    units.reserveCapacity(units.count + value.utf16.count)
    units.append(contentsOf: KotlinStringSurrogateEncoding.UTF16CodeUnits(value))
}

/// The Kotlin UTF-16 code unit at `index`, scanning scalars only until the
/// target is reached instead of materializing the whole code-unit array.
/// Returns nil when `index` is out of bounds; identical to
/// `runtimeKotlinStringUTF16CodeUnits(value)[index]` for in-range indexes.
func runtimeKotlinStringUTF16CodeUnit(_ value: String, at index: Int) -> UInt16? {
    guard index >= 0 else { return nil }
    for (offset, unit) in KotlinStringSurrogateEncoding.UTF16CodeUnits(value).enumerated() {
        if offset == index { return unit }
    }
    return nil
}

/// UTF-16 code-unit count without allocating the unit array.
func runtimeKotlinStringUTF16Length(_ value: String) -> Int {
    KotlinStringSurrogateEncoding.UTF16CodeUnits(value).reduce(0) { count, _ in count + 1 }
}

/// Reconstructs a Swift String from Kotlin UTF-16 code units, preserving
/// isolated surrogates through the compiler/runtime marker representation.
func runtimeKotlinStringFromUTF16CodeUnits(_ units: [UInt16]) -> String {
    KotlinStringSurrogateEncoding.fromUTF16CodeUnits(units)
}

/// Kotlin String equality compares the underlying UTF-16 code-unit sequence.
/// Swift String equality uses canonical equivalence, so it cannot be used for
/// the default Kotlin String equality contract.
@inline(__always)
func runtimeStringsEqual(_ lhs: String, _ rhs: String) -> Bool {
    KotlinStringSurrogateEncoding.UTF16CodeUnits(lhs).elementsEqual(KotlinStringSurrogateEncoding.UTF16CodeUnits(rhs))
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
        // A lone surrogate half is a valid Kotlin Char; keep it (as the
        // isolated-surrogate marker) so it can recombine into a pair later.
        var code = raw
        if let pointer = UnsafeMutableRawPointer(bitPattern: raw),
           runtimeIsObjectPointer(pointer),
           let charBox = tryCast(pointer, to: RuntimeCharBox.self)
        {
            code = Int(charBox.value)
        }
        if (0xD800 ... 0xDFFF).contains(code) {
            return runtimeKotlinStringFromUTF16CodeUnits([UInt16(code)])
        }
        return "?"
    }
    return KotlinStringSurrogateEncoding.encode(String(scalar))
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

/// Boxes an internal escaped string. Foreign UTF-8 enters via kk_string_from_utf8.
func runtimeMakeStringRaw(_ value: String) -> Int {
    registerRuntimeObject(RuntimeStringBox(value))
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
        box[index] = value
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
    runtimeMakeListRaw(runtimeKotlinStringUTF16CodeUnits(source).map { Int($0) })
}

func runtimeStringIndexOfRaw(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let source = runtimeStringUTF16CodeUnits(strRaw)
    let other = runtimeStringUTF16CodeUnits(otherRaw)

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
    let source = runtimeStringUTF16CodeUnits(strRaw)
    let other = runtimeStringUTF16CodeUnits(otherRaw)

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
        units: runtimeStringUTF16CodeUnits(strRaw),
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown
    )
}

func runtimeStringIndexOfLastFromRaw(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringIndexOfLast(
        units: runtimeStringUTF16CodeUnits(strRaw),
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        outThrown: outThrown
    )
}

private func runtimeStringIndexOfFirst(
    units: [UInt16],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (index, unit) in units.enumerated() {
        let charRaw = Int(unit)
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
    units: [UInt16],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else { return -1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var lastIdx = -1
    for (index, unit) in units.enumerated() {
        let charRaw = Int(unit)
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

/// `String.lowercase()` with the unconditional Unicode mappings plus the
/// context-sensitive Final_Sigma rule (Σ -> ς at the end of a word, else σ),
/// which `String.lowercased()` does not apply.
func runtimeKotlinLowercased(_ source: String) -> String {
    let scalars = Array(source.unicodeScalars)
    guard scalars.contains(where: { $0.value == 0x3A3 }) else { return source.lowercased() }

    func lowercased(_ range: Range<Int>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[range])
        return String(view).lowercased()
    }
    func isFinalSigma(at index: Int) -> Bool {
        var before = index - 1
        while before >= 0, scalars[before].properties.isCaseIgnorable { before -= 1 }
        guard before >= 0, scalars[before].properties.isCased else { return false }
        var after = index + 1
        while after < scalars.count, scalars[after].properties.isCaseIgnorable { after += 1 }
        return after >= scalars.count || !scalars[after].properties.isCased
    }

    var result = ""
    var segmentStart = 0
    for index in scalars.indices where scalars[index].value == 0x3A3 {
        result += lowercased(segmentStart ..< index)
        result += isFinalSigma(at: index) ? "\u{3C2}" : "\u{3C3}"
        segmentStart = index + 1
    }
    return result + lowercased(segmentStart ..< scalars.count)
}

func runtimeSplitString(_ source: String, delimiter: String, limit: Int = 0) -> [String] {
    runtimeSplitStringLimit(source, delimiter: delimiter, ignoreCase: false, limit: limit)
}

/// Index of the first occurrence of `needle` in `units` at or after `start`,
/// comparing UTF-16 code units the way Kotlin's `indexOf` does. Foundation's
/// `range(of:)` is unsuitable: it matches canonically equivalent sequences
/// ("e\u{301}" ~ "é") and applies full case folding (ß ~ SS).
private func runtimeIndexOfCodeUnits(
    _ needle: [UInt16],
    in units: [UInt16],
    from start: Int,
    ignoreCase: Bool
) -> Int? {
    let lastStart = units.count - needle.count
    guard start <= lastStart else { return nil }
    var candidate = start
    while candidate <= lastStart {
        var offset = 0
        while offset < needle.count {
            let lhs = units[candidate + offset]
            let rhs = needle[offset]
            if lhs != rhs, !(ignoreCase && runtimeCharsEqualIgnoringCase(lhs, rhs)) { break }
            offset += 1
        }
        if offset == needle.count { return candidate }
        candidate += 1
    }
    return nil
}

func runtimeReplacingStringCodeUnits(
    _ source: String, old: String, new: String, ignoreCase: Bool = false, firstOnly: Bool = false
) -> String {
    let units = runtimeKotlinStringUTF16CodeUnits(source)
    let needle = runtimeKotlinStringUTF16CodeUnits(old)
    let replacement = runtimeKotlinStringUTF16CodeUnits(new)
    var result: [UInt16] = []
    var cursor = 0
    while cursor <= units.count,
          let match = runtimeIndexOfCodeUnits(needle, in: units, from: cursor, ignoreCase: ignoreCase)
    {
        result.append(contentsOf: units[cursor ..< match])
        result.append(contentsOf: replacement)
        cursor = match + needle.count
        if firstOnly { break }
        if needle.isEmpty {
            if cursor == units.count { break }
            result.append(units[cursor])
            cursor += 1
        }
    }
    result.append(contentsOf: units[cursor ..< units.count])
    return runtimeKotlinStringFromUTF16CodeUnits(result)
}

func runtimeSplitStringLimit(
    _ source: String,
    delimiter: String,
    ignoreCase: Bool,
    limit: Int
) -> [String] {
    if delimiter.isEmpty {
        return runtimeSplitStringOnEmptyDelimiter(source, limit: limit)
    }
    if source.isEmpty {
        return [""]
    }

    let units = runtimeKotlinStringUTF16CodeUnits(source)
    let needle = runtimeKotlinStringUTF16CodeUnits(delimiter)
    func piece(_ range: Range<Int>) -> String {
        runtimeKotlinStringFromUTF16CodeUnits(Array(units[range]))
    }
    var result: [String] = []
    var cursor = 0
    while true {
        if limit > 0, result.count == limit - 1 {
            result.append(piece(cursor ..< units.count))
            return result
        }
        guard let match = runtimeIndexOfCodeUnits(needle, in: units, from: cursor, ignoreCase: ignoreCase) else {
            result.append(piece(cursor ..< units.count))
            return result
        }
        result.append(piece(cursor ..< match))
        cursor = match + needle.count
    }
}

/// Splits at every UTF-16 code-unit boundary, including the boundaries at both
/// ends of the source. Kotlin treats an empty string delimiter as a zero-width
/// match at each such position.
private func runtimeSplitStringOnEmptyDelimiter(_ source: String, limit: Int) -> [String] {
    let codeUnits = runtimeKotlinStringUTF16CodeUnits(source)
    var result: [String] = []
    result.reserveCapacity(limit > 0 ? min(limit, codeUnits.count + 2) : codeUnits.count + 2)

    var fieldStart = 0
    var matchPosition = 0
    while matchPosition <= codeUnits.count {
        if limit > 0 && result.count == limit - 1 {
            break
        }
        result.append(
            runtimeKotlinStringFromUTF16CodeUnits(
                Array(codeUnits[fieldStart ..< matchPosition])
            )
        )
        fieldStart = matchPosition
        matchPosition += 1
    }

    result.append(
        runtimeKotlinStringFromUTF16CodeUnits(
            Array(codeUnits[fieldStart ..< codeUnits.count])
        )
    )
    return result
}
