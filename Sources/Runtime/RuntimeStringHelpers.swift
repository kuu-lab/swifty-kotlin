import Foundation
import RuntimeABI

func runtimeStringUTF16CodeUnits(_ raw: Int) -> [UInt16] {
    if let box = runtimeStringBox(fromRaw: raw) {
        return box.utf16CodeUnits
    }
    return runtimeKotlinStringUTF16CodeUnits(runtimeStringFromRawOrPanic(raw, caller: #function))
}

func runtimeKotlinStringUTF16CodeUnits(_ value: String) -> [UInt16] {
    KotlinStringSurrogateEncoding.utf16CodeUnits(value)
}

func runtimeAppendKotlinUTF16CodeUnits(of value: String, to units: inout [UInt16]) {
    units.reserveCapacity(units.count + value.utf16.count)
    units.append(contentsOf: KotlinStringSurrogateEncoding.UTF16CodeUnits(value))
}

func runtimeKotlinStringUTF16CodeUnit(_ value: String, at index: Int) -> UInt16? {
    guard index >= 0 else { return nil }
    for (offset, unit) in KotlinStringSurrogateEncoding.UTF16CodeUnits(value).enumerated() {
        if offset == index { return unit }
    }
    return nil
}

func runtimeKotlinStringUTF16Length(_ value: String) -> Int {
    KotlinStringSurrogateEncoding.UTF16CodeUnits(value).reduce(0) { count, _ in count + 1 }
}

func runtimeKotlinStringFromUTF16CodeUnits(_ units: [UInt16]) -> String {
    KotlinStringSurrogateEncoding.fromUTF16CodeUnits(units)
}

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

func runtimeStringFromRawOrPanic(_ raw: Int, caller: StaticString) -> String {
    if let s = runtimeStringFromRaw(raw) {
        return s
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
}

func runtimeCharacterFromRaw(_ raw: Int) -> String {
    guard let scalar = runtimeUnicodeScalarFromRaw(raw) else {
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

func runtimeMakeStringRaw(_ value: String) -> Int {
    registerRuntimeObject(RuntimeStringBox(value))
}

func runtimeMakeUTF8StringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

func runtimeMakeListRaw(_ values: [Int]) -> Int {
    // Route through registerRuntimeObject so the box picks up the canonical
    // `kotlin.collections.List` nominal identity and Iterable/Sequence itables
    // like every other list factory; the hand-rolled registration left these
    // lists answering `is List<*>`/`is Iterable<*>` false (KUU-4036).
    registerRuntimeObject(RuntimeListBox(elements: values))
}

func runtimeMakeArrayRaw(_ values: [Int]) -> Int {
    let box = RuntimeArrayBox(length: values.count)
    for (index, value) in values.enumerated() {
        box[index] = value
    }
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: pointer)
        state.objectPointers.insert(key)
        box.recordManagedHeapFieldsLocked(owner: key, state: &state)
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

/// Applies full case mapping only to valid Unicode runs. NUL and isolated
/// surrogate units are uncased boundaries and must survive foreign string APIs.
/// Decode before mapping and re-encode afterwards so literal private-use scalars
/// cannot be confused with the runtime's escaped surrogate representation.
func runtimeKotlinCaseMapped(_ source: String, mapping: (String) -> String) -> String {
    let units = runtimeKotlinStringUTF16CodeUnits(source)
    var result: [UInt16] = []
    result.reserveCapacity(units.count)
    var start = 0
    var index = 0

    func appendMappedRun(endingAt end: Int) {
        guard start < end else { return }
        let run = String(decoding: units[start ..< end], as: UTF16.self)
        result.append(contentsOf: mapping(run).utf16)
    }

    while index < units.count {
        let unit = units[index]
        if (0xD800 ... 0xDBFF).contains(unit), index + 1 < units.count,
           (0xDC00 ... 0xDFFF).contains(units[index + 1])
        {
            index += 2
            continue
        }
        if unit == 0 || (0xD800 ... 0xDFFF).contains(unit) {
            appendMappedRun(endingAt: index)
            result.append(unit)
            start = index + 1
        }
        index += 1
    }
    appendMappedRun(endingAt: units.count)
    return runtimeKotlinStringFromUTF16CodeUnits(result)
}

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
