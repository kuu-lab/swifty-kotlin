import Foundation
import RuntimeABI

func runtimeKPropertyStubToString(_ property: RuntimeKPropertyStub) -> String {
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: property.name)) ?? "<anonymous>"
    let returnType = runtimeReflectionObject(
        from: property.returnTypeKTypeRaw,
        as: RuntimeKTypeBox.self
    ).map(runtimeKTypeToString)
        ?? extractString(from: UnsafeMutableRawPointer(bitPattern: property.returnType))
        ?? "kotlin.Any?"
    return "\(property.isMutable ? "var" : "val") \(name): \(returnType)"
}

@_cdecl("__kk_print_raw")
public func __kk_print_raw(_ messageRaw: Int) {
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? "null"
    Swift.print(KotlinStringSurrogateEncoding.printableString(message), terminator: "")
}

@_cdecl("__kk_println_raw")
public func __kk_println_raw(_ messageRaw: Int) {
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? "null"
    Swift.print(KotlinStringSurrogateEncoding.printableString(message), terminator: "\n")
}

@_cdecl("__kk_printStderr")
public func __kk_printStderr(_ messageRaw: Int) -> Int {
    let message = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? ""
    FileHandle.standardError.write(Data(KotlinStringSurrogateEncoding.printableString(message).utf8))
    return 0
}

/// KSP-615: single low-level console input bridge behind `kotlin.io.readLine` /
/// `readln` / `readlnOrNull`. Returns a pointer to a runtime string on success,
/// or `runtimeNullSentinelInt` on EOF; nullability and the `readln` EOF throw
/// live in `Stdlib/kotlin/io/Console.kt`.
@_cdecl("__kk_readline_raw")
public func __kk_readline_raw() -> Int {
    guard let line = readLine() else {
        return runtimeNullSentinelInt
    }
    let utf8 = Array(line.utf8)
    if utf8.isEmpty {
        var emptyByte: UInt8 = 0
        return withUnsafePointer(to: &emptyByte) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, 0))
        }
    }
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

func runtimeRenderAnyForPrint(_ value: Int) -> String {
    if value == runtimeNullSentinelInt {
        return "null"
    }
    guard let raw = UnsafeMutableRawPointer(bitPattern: value) else {
        return String(value)
    }
    // KUU-1352: coroutine job/task handles live in the liveness registry, not
    // objectPointers — render kotlinx's `Name{State}@hex` before the
    // pointer-type gate drops them into the numeric fallback.
    if let rendered = runtimeJobHandleDebugString(value) {
        return rendered
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: raw))
    }
    guard isObjectPointer else {
        return String(value)
    }
    if let classText = runtimeJavaClassToStringText(value) {
        return classText
    }
    if let dispatcher = tryCast(raw, to: RuntimeDispatcher.self),
       let name = dispatcher.displayName {
        return name
    }
    if runtimeIsUnitBox(value) {
        return "kotlin.Unit"
    }
    if let boolBox = tryCast(raw, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let intBox = tryCast(raw, to: RuntimeIntBox.self) {
        return intBox.renderedString
    }
    if let stringBox = tryCast(raw, to: RuntimeStringBox.self) {
        return stringBox.value
    }
    if let doubleBox = tryCast(raw, to: RuntimeDoubleBox.self) {
        return runtimeFormatFloatingPoint(doubleBox.value)
    }
    if let floatBox = tryCast(raw, to: RuntimeFloatBox.self) {
        return runtimeFormatFloatingPoint(floatBox.value)
    }
    if let longBox = tryCast(raw, to: RuntimeLongBox.self) {
        return String(longBox.value)
    }
    if let ulongBox = tryCast(raw, to: RuntimeULongBox.self) {
        return String(UInt(bitPattern: ulongBox.value))
    }
    if let charBox = tryCast(raw, to: RuntimeCharBox.self) {
        return runtimeCharacterFromRaw(charBox.value)
    }
    if let throwableString = runtimeThrowableToString(value) {
        return throwableString
    }
    if let instantBox = tryCast(raw, to: RuntimeInstantBox.self) {
        return runtimeInstantToString(instantBox)
    }
    if let localeBox = tryCast(raw, to: RuntimeLocaleBox.self) {
        return runtimeLocaleToString(localeBox)
    }
    if let listBox = runtimeListBox(from: value) {
        return "[\(listBox.values.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let setBox = tryCast(raw, to: RuntimeSetBox.self) {
        return "[\(setBox.values.map(runtimeRenderAnyForPrint).joined(separator: ", "))]"
    }
    if let mapBox = tryCast(raw, to: RuntimeMapBox.self) {
        let rendered = zip(mapBox.keyValues, mapBox.entryValues).map { key, value in
            "\(runtimeRenderAnyForPrint(key))=\(runtimeRenderAnyForPrint(value))"
        }.joined(separator: ", ")
        return "{\(rendered)}"
    }
    if tryCast(raw, to: RuntimeRangeBox.self) != nil {
        return runtimeElementToString(value)
    }
    if tryCast(raw, to: RuntimeDoubleRangeBox.self) != nil
        || tryCast(raw, to: RuntimeFloatRangeBox.self) != nil
    {
        return runtimeElementToString(value)
    }
    if let pairBox = tryCast(raw, to: RuntimePairBox.self) {
        let first = runtimeRenderAnyForPrint(pairBox.firstValue)
        let second = runtimeRenderAnyForPrint(pairBox.secondValue)
        if runtimeIsMapEntry(rawValue: value) {
            return "\(first)=\(second)"
        }
        if runtimeObjectTypeID(rawValue: value) == indexedValueRuntimeTypeID {
            return "IndexedValue(index=\(first), value=\(second))"
        }
        return "(\(first), \(second))"
    }
    if let tripleBox = tryCast(raw, to: RuntimeTripleBox.self) {
        let first = runtimeRenderAnyForPrint(tripleBox.firstValue)
        let second = runtimeRenderAnyForPrint(tripleBox.secondValue)
        let third = runtimeRenderAnyForPrint(tripleBox.thirdValue)
        return "(\(first), \(second), \(third))"
    }
    if tryCast(raw, to: RuntimeIndexingIterableBox.self) != nil {
        let hex = String(format: "%x", UInt(bitPattern: raw) % 0x1_0000_0000)
        return "kotlin.collections.IndexingIterable@\(hex)"
    }
    if let arrayBox = tryCast(raw, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        return runtimeUnsignedArrayToString(value, box: arrayBox)
            ?? runtimeFloatingPointArrayToString(value, box: arrayBox)
            ?? runtimeArrayIdentityToString(value)
    }
    if let sbBox = tryCast(raw, to: RuntimeStringBuilderBox.self) {
        return sbBox.stringValue
    }
    if let kclassBox = tryCast(raw, to: RuntimeKClassBox.self) {
        return runtimeKClassToString(kclassBox)
    }
    if let property = tryCast(raw, to: RuntimeKPropertyStub.self) {
        return runtimeKPropertyStubToString(property)
    }
    if let ktypeProjectionBox = tryCast(raw, to: RuntimeKTypeProjectionBox.self) {
        return runtimeKTypeProjectionToString(ktypeProjectionBox)
    }
    if let ktypeBox = tryCast(raw, to: RuntimeKTypeBox.self) {
        return runtimeKTypeToString(ktypeBox)
    }
    if let rendered = runtimeRenderIndexedValueObject(value, render: runtimeRenderAnyForPrint) {
        return rendered
    }
    if let resultBox = tryCast(raw, to: RuntimeResultBox.self) {
        return runtimeResultToString(resultBox, render: runtimeRenderAnyForPrint)
    }
    if let rendered = runtimeJobWrapperDebugString(value) {
        return rendered
    }
    if let rendered = runtimeDefaultObjectIdentityToString(value) {
        return rendered
    }
    return "<object \(raw)>"
}

func runtimeRenderAnyForPrint(_ value: RuntimeValue) -> String {
    switch value.tag {
    case RuntimeValue.stringTag:
        guard let data = UnsafePointer<UInt8>(bitPattern: value.payload0) else {
            return "null"
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    case RuntimeValue.charTag:
        return UnicodeScalar(value.payload0).map { String(Character($0)) } ?? "?"
    default:
        return runtimeRenderAnyForPrint(value.payload0)
    }
}

private func runtimeNormalizeScientificExponent(_ rendered: String) -> String {
    guard let exponentIndex = rendered.firstIndex(of: "E") ?? rendered.firstIndex(of: "e") else {
        return rendered
    }
    let mantissa = runtimeNormalizeScientificMantissa(String(rendered[..<exponentIndex]))
    var exponent = String(rendered[rendered.index(after: exponentIndex)...])
    if exponent.hasPrefix("+") {
        exponent.removeFirst()
    }
    while exponent.count > 1, exponent.first == "0" {
        exponent.removeFirst()
    }
    if exponent.hasPrefix("-0"), exponent.count > 2 {
        exponent.remove(at: exponent.index(after: exponent.startIndex))
    }
    return "\(mantissa)E\(exponent)"
}

private func runtimeNormalizeScientificMantissa(_ mantissa: String) -> String {
    guard let dotIndex = mantissa.firstIndex(of: ".") else {
        return mantissa + ".0"
    }
    let integerPart = String(mantissa[..<dotIndex])
    var fractionalPart = String(mantissa[mantissa.index(after: dotIndex)...])
    while fractionalPart.last == "0" {
        fractionalPart.removeLast()
    }
    if fractionalPart.isEmpty {
        fractionalPart = "0"
    }
    return "\(integerPart).\(fractionalPart)"
}

private func runtimeScientificString(fromFixed rendered: String) -> String {
    var body = rendered
    var sign = ""
    if body.hasPrefix("-") {
        sign = "-"
        body.removeFirst()
    } else if body.hasPrefix("+") {
        body.removeFirst()
    }

    let components = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let integerPart = String(components.first ?? "")
    let fractionalPart = components.count > 1 ? String(components[1]) : ""

    let trimmedInteger = integerPart.drop(while: { $0 == "0" })
    let exponent: Int
    let significantDigits: String

    if !trimmedInteger.isEmpty {
        exponent = trimmedInteger.count - 1
        significantDigits = String(trimmedInteger) + fractionalPart
    } else if let firstNonZeroFraction = fractionalPart.firstIndex(where: { $0 != "0" }) {
        exponent = -fractionalPart.distance(from: fractionalPart.startIndex, to: firstNonZeroFraction) - 1
        significantDigits = String(fractionalPart[firstNonZeroFraction...])
    } else {
        return sign + "0.0E0"
    }

    let firstDigit = String(significantDigits.prefix(1))
    var mantissaFraction = String(significantDigits.dropFirst())
    while mantissaFraction.last == "0" {
        mantissaFraction.removeLast()
    }
    if mantissaFraction.isEmpty {
        mantissaFraction = "0"
    }
    return "\(sign)\(firstDigit).\(mantissaFraction)E\(exponent)"
}

/// Kotlin (matching java.lang.Double/Float.toString) uses scientific notation
/// when the magnitude is >= 1e7 or < 1e-3.
private func runtimeFinishFloatingPointFormat(rendered: String, useScientific: Bool) -> String {
    if rendered.contains("e") || rendered.contains("E") {
        return runtimeNormalizeScientificExponent(rendered)
    }
    if useScientific {
        return runtimeScientificString(fromFixed: rendered)
    }
    return rendered
}

/// JDK-19+ `FloatingDecimal` selection: when the shortest round-tripping
/// decimal has length 1, the emitted decimal is instead the one closest to
/// the exact value among ALL length-1-or-2 decimals that round-trip. Ryu's
/// 1-digit answer (e.g. `1e-323`, `3e-45`) therefore loses to a nearer
/// 2-digit decimal (`9.9E-324`, `2.8E-45`). Returns nil when the Ryu form
/// already has 2+ significant digits.
private func runtimeJavaTwoDigitDecimal(
    _ magnitude: Double,
    ryuRendered: String,
    expansionPrecision: Int,
    reparsesToMagnitude: (String) -> Bool
) -> String? {
    var mantissa = ryuRendered
    if let eIdx = mantissa.firstIndex(of: "e") ?? mantissa.firstIndex(of: "E") {
        mantissa = String(mantissa[..<eIdx])
    }
    var digitsOnly = mantissa.filter(\.isNumber)
    while digitsOnly.first == "0" { digitsOnly.removeFirst() }
    while digitsOnly.last == "0" { digitsOnly.removeLast() }
    guard digitsOnly.count == 1 else { return nil }

    // Exact decimal expansion of the binary value: every binary float has a
    // finite decimal expansion (<= ~767 significant digits for Double,
    // <= ~150 for Float), so a large fixed precision captures all digits.
    let expansion = String(format: "%.\(expansionPrecision)e", magnitude)
    guard let eIdx = expansion.firstIndex(of: "e"),
          let e10 = Int(expansion[expansion.index(after: eIdx)...])
    else { return nil }
    let digits = expansion[..<eIdx].filter(\.isNumber).compactMap(\.wholeNumberValue)
    guard digits.count >= 3 else { return nil }

    func canonical(_ sig: Int, _ i: Int) -> (sig: Int, i: Int) {
        var s = sig, j = i
        while s % 10 == 0 { s /= 10; j += 1 }
        return (s, j)
    }
    func inRoundTripSet(_ sig: Int, _ i: Int) -> Bool {
        reparsesToMagnitude("\(sig)e\(i)")
    }
    func closerOfPair(
        _ floorC: (sig: Int, i: Int), _ ceilC: (sig: Int, i: Int),
        roundDigit: Int, tailNonZero: Bool
    ) -> (sig: Int, i: Int) {
        if roundDigit > 5 || (roundDigit == 5 && tailNonZero) { return ceilC }
        if roundDigit < 5 { return floorC }
        return floorC.sig % 2 == 0 ? floorC : ceilC
    }

    // Length-1 numerals are a subset of the length-2 grid, so whenever any
    // length-2 decimal round-trips it is at least as close to the value as
    // every length-1 candidate and wins outright.
    let i2 = e10 - 1
    var inside2: [(sig: Int, i: Int)] = []
    for raw in [digits[0] * 10 + digits[1], digits[0] * 10 + digits[1] + 1] {
        let c = canonical(raw, i2)
        if inRoundTripSet(c.sig, c.i), !inside2.contains(where: { $0 == c }) {
            inside2.append(c)
        }
    }
    let winner: (sig: Int, i: Int)
    if let first = inside2.first {
        winner = inside2.count == 2
            ? closerOfPair(first, inside2[1], roundDigit: digits[2],
                           tailNonZero: digits.dropFirst(3).contains { $0 != 0 })
            : first
    } else {
        var inside1: [(sig: Int, i: Int)] = []
        for raw in [digits[0], digits[0] + 1] {
            let c = canonical(raw, e10)
            if inRoundTripSet(c.sig, c.i), !inside1.contains(where: { $0 == c }) {
                inside1.append(c)
            }
        }
        guard let first = inside1.first else { return nil }
        winner = inside1.count == 2
            ? closerOfPair(first, inside1[1], roundDigit: digits[1],
                           tailNonZero: digits.dropFirst(2).contains { $0 != 0 })
            : first
    }

    let sig = String(winner.sig)
    let n = sig.count, i = winner.i
    let e = n + i - 1
    if e >= -3 && e < 0 {
        return "0." + String(repeating: "0", count: -(n + i)) + sig
    }
    if e >= 0 && e < 7 {
        if i >= 0 { return sig + String(repeating: "0", count: i) + ".0" }
        return "\(sig.prefix(n + i)).\(sig.dropFirst(n + i))"
    }
    if n == 1 { return "\(sig).0E\(e)" }
    return "\(sig.prefix(1)).\(sig.dropFirst())E\(e)"
}

func runtimeFormatFloatingPoint(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value == .infinity { return "Infinity" }
    if value == -.infinity { return "-Infinity" }
    // Explicit guard: String(describing:) may drop the sign of -0.0 on some platforms.
    if value == 0.0 && value.sign == .minus { return "-0.0" }
    // Swift's Ryu selects the 1-significant-digit form (5e-324) for the minimum
    // subnormal, but Java's FloatingDecimal emits 4.9E-324.  Both strings
    // round-trip to the same bit pattern, but we must match the Java convention.
    if value == Double.leastNonzeroMagnitude { return "4.9E-324" }
    if value == -Double.leastNonzeroMagnitude { return "-4.9E-324" }
    let magnitude = abs(value)
    if let selected = runtimeJavaTwoDigitDecimal(magnitude, ryuRendered: String(describing: value),
        expansionPrecision: 800, reparsesToMagnitude: { Double($0) == magnitude }) {
        return (value < 0 ? "-" : "") + selected
    }
    return runtimeFinishFloatingPointFormat(
        rendered: String(describing: value),
        useScientific: magnitude != 0 && (magnitude >= 1e7 || magnitude < 1e-3)
    )
}

func runtimeFormatFloatingPoint(_ value: Float) -> String {
    if value.isNaN { return "NaN" }
    if value == .infinity { return "Infinity" }
    if value == -.infinity { return "-Infinity" }
    // Explicit guard: String(describing:) may drop the sign of -0.0 on some platforms.
    if value == 0.0 && value.sign == .minus { return "-0.0" }
    // Same issue for Float: Ryu gives 1e-45, Java gives 1.4E-45.
    if value == Float.leastNonzeroMagnitude { return "1.4E-45" }
    if value == -Float.leastNonzeroMagnitude { return "-1.4E-45" }
    let magnitude = abs(value)
    let doubleMagnitude = Double(magnitude)
    if let selected = runtimeJavaTwoDigitDecimal(doubleMagnitude, ryuRendered: String(describing: value),
        expansionPrecision: 160, reparsesToMagnitude: { Float($0) == magnitude }) {
        return (value < 0 ? "-" : "") + selected
    }
    return runtimeFinishFloatingPointFormat(
        rendered: String(describing: value),
        useScientific: magnitude != 0 && (magnitude >= 1e7 || magnitude < 1e-3)
    )
}
