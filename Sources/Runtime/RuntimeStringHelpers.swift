// Shared helper functions for RuntimeStringStdlib and its split-out files.
// Split out from `RuntimeStringStdlib.swift`.

import Foundation
import RuntimeABI

func runtimeStringScalars(_ raw: Int) -> [UnicodeScalar] {
    Array(runtimeStringFromRawOrPanic(raw, caller: #function).unicodeScalars)
}

func runtimeStringUTF16CodeUnits(_ raw: Int) -> [UInt16] {
    runtimeStringBoxFromRawOrPanic(raw, caller: #function).utf16CodeUnits
}

/// Returns Kotlin's UTF-16 code units while decoding the compiler's isolated
/// surrogate markers back to their original values.
func runtimeKotlinStringUTF16CodeUnits(_ value: String) -> [UInt16] {
    var result: [UInt16] = []
    result.reserveCapacity(value.utf16.count)
    for scalar in value.unicodeScalars {
        let scalarValue = scalar.value
        if let codeUnitValue = KotlinStringSurrogateEncoding.codeUnitValue(for: scalarValue) {
            result.append(UInt16(codeUnitValue))
        } else if scalarValue <= 0xFFFF {
            result.append(UInt16(scalarValue))
        } else {
            let offset = scalarValue - 0x10000
            result.append(UInt16(0xD800 + (offset >> 10)))
            result.append(UInt16(0xDC00 + (offset & 0x03FF)))
        }
    }
    return result
}

func runtimeKotlinStringUTF16Length(_ value: String) -> Int {
    // Isolated-surrogate markers live in the BMP private-use range, so each
    // marker is one UTF-16 code unit exactly like the scalar it replaces and
    // `utf16.count` already equals the Kotlin code-unit count — no need to
    // materialize the decoded array just to count it.
    value.utf16.count
}

/// Lazily decodes Kotlin UTF-16 code units from a string's scalars — the same
/// decoding as `runtimeKotlinStringUTF16CodeUnits` — without allocating the
/// whole array. Single-index reads stop once the requested unit is emitted.
struct RuntimeKotlinStringUTF16CodeUnitIterator: IteratorProtocol {
    private var scalars: String.UnicodeScalarView.Iterator
    private var pendingLowSurrogate: UInt16?

    init(_ value: String) {
        scalars = value.unicodeScalars.makeIterator()
    }

    mutating func next() -> UInt16? {
        if let pending = pendingLowSurrogate {
            pendingLowSurrogate = nil
            return pending
        }
        guard let scalar = scalars.next() else {
            return nil
        }
        let scalarValue = scalar.value
        if let codeUnitValue = KotlinStringSurrogateEncoding.codeUnitValue(for: scalarValue) {
            return UInt16(codeUnitValue)
        }
        if scalarValue <= 0xFFFF {
            return UInt16(scalarValue)
        }
        let offset = scalarValue - 0x10000
        pendingLowSurrogate = UInt16(0xDC00 + (offset & 0x03FF))
        return UInt16(0xD800 + (offset >> 10))
    }
}

/// Returns the Kotlin UTF-16 code unit at `index`, decoding `value` only as
/// far as needed instead of materializing the whole code-unit array. Nil when
/// `index` is out of bounds; callers that need the exact length for a
/// diagnostic can compute `runtimeKotlinStringUTF16Length(value)` separately.
func runtimeKotlinStringUTF16CodeUnit(at index: Int, in value: String) -> UInt16? {
    guard index >= 0 else {
        return nil
    }
    var iterator = RuntimeKotlinStringUTF16CodeUnitIterator(value)
    var remaining = index
    while remaining > 0 {
        guard iterator.next() != nil else {
            return nil
        }
        remaining -= 1
    }
    return iterator.next()
}

/// Reconstructs a Swift String from Kotlin UTF-16 code units, preserving
/// isolated surrogates through the compiler/runtime marker representation.
func runtimeKotlinStringFromUTF16CodeUnits(_ units: [UInt16]) -> String {
    var result = ""
    result.reserveCapacity(units.count)
    var index = 0
    while index < units.count {
        let codeUnit = UInt32(units[index])
        if (0xD800 ... 0xDBFF).contains(codeUnit),
           index + 1 < units.count,
           (0xDC00 ... 0xDFFF).contains(UInt32(units[index + 1]))
        {
            let low = UInt32(units[index + 1])
            let combined = 0x10000 + ((codeUnit - 0xD800) << 10) + (low - 0xDC00)
            result.unicodeScalars.append(UnicodeScalar(combined)!)
            index += 2
        } else if let markerValue = KotlinStringSurrogateEncoding.markerValue(for: codeUnit),
                  let marker = UnicodeScalar(markerValue)
        {
            result.unicodeScalars.append(marker)
            index += 1
        } else {
            result.unicodeScalars.append(UnicodeScalar(codeUnit)!)
            index += 1
        }
    }
    return result
}

/// Kotlin String equality compares the underlying UTF-16 code-unit sequence.
/// Swift String equality uses canonical equivalence, so it cannot be used for
/// the default Kotlin String equality contract.
@inline(__always)
func runtimeStringsEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf16.elementsEqual(rhs.utf16)
}

func runtimeStringFromScalars(_ scalars: some Sequence<UnicodeScalar>) -> String {
    String(String.UnicodeScalarView(scalars))
}

func runtimeStringFromRaw(_ raw: Int) -> String? {
    runtimeStringBoxFromRaw(raw)?.value
}

/// Boxed variant of `runtimeStringFromRaw` returning the `RuntimeStringBox`
/// itself so callers can reuse its memoized UTF-16 code units.
func runtimeStringBoxFromRaw(_ raw: Int) -> RuntimeStringBox? {
    if raw == runtimeNullSentinelInt {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractStringBox(from: pointer)
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

/// Fail-fast variant of `runtimeStringBoxFromRaw` mirroring
/// `runtimeStringFromRawOrPanic`.
func runtimeStringBoxFromRawOrPanic(_ raw: Int, caller: StaticString) -> RuntimeStringBox {
    if let box = runtimeStringBoxFromRaw(raw) {
        return box
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
    if delimiter.isEmpty {
        return runtimeSplitStringOnEmptyDelimiter(source, limit: limit)
    }
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
    if delimiter.isEmpty {
        return runtimeSplitStringOnEmptyDelimiter(source, limit: limit)
    }
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
