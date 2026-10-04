/// Opaque runtime storage for floating-point ranges with a `Double` element.
final class RuntimeDoubleRangeBox {
    let first: Double
    let last: Double
    let endExclusive: Bool

    init(first: Double, last: Double, endExclusive: Bool = false) {
        self.first = first
        self.last = last
        self.endExclusive = endExclusive
    }
}

/// Opaque runtime storage for floating-point ranges with a `Float` element.
final class RuntimeFloatRangeBox {
    let first: Float
    let last: Float
    let endExclusive: Bool

    init(first: Float, last: Float, endExclusive: Bool = false) {
        self.first = first
        self.last = last
        self.endExclusive = endExclusive
    }
}

private func runtimeDoubleRangeBox(from raw: Int) -> RuntimeDoubleRangeBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    guard runtimeIsObjectPointer(pointer) else {
        return nil
    }
    return tryCast(pointer, to: RuntimeDoubleRangeBox.self)
}

private func runtimeFloatRangeBox(from raw: Int) -> RuntimeFloatRangeBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    guard runtimeIsObjectPointer(pointer) else {
        return nil
    }
    return tryCast(pointer, to: RuntimeFloatRangeBox.self)
}

private func runtimeCoerceInError(minimum: String, maximum: String) -> Int {
    runtimeAllocateIllegalArgumentException(
        message: "Cannot coerce value to an empty range: maximum \(maximum) is less than minimum \(minimum)."
    )
}

private func doubleValue(from bits: Int) -> Double {
    if let pointer = UnsafeMutableRawPointer(bitPattern: bits),
       runtimeIsObjectPointer(pointer)
    {
        if let box = tryCast(pointer, to: RuntimeDoubleBox.self) {
            return box.value
        }
        if let box = tryCast(pointer, to: RuntimeFloatBox.self) {
            return Double(box.value)
        }
    }
    return Double(bitPattern: UInt64(bitPattern: Int64(bits)))
}

private func doubleBits(_ value: Double) -> Int {
    Int(bitPattern: UInt(value.bitPattern))
}

private func floatValue(from bits: Int) -> Float {
    if let pointer = UnsafeMutableRawPointer(bitPattern: bits),
       runtimeIsObjectPointer(pointer)
    {
        if let box = tryCast(pointer, to: RuntimeFloatBox.self) {
            return box.value
        }
        if let box = tryCast(pointer, to: RuntimeDoubleBox.self) {
            return Float(box.value)
        }
    }
    return Float(bitPattern: UInt32(truncatingIfNeeded: bits))
}

private func floatBits(_ value: Float) -> Int {
    Int(Int32(bitPattern: value.bitPattern))
}

@_cdecl("__kk_double_rangeTo")
public func __kk_double_rangeTo(_ lhsBits: Int, _ rhsBits: Int) -> Int {
    registerRuntimeObject(RuntimeDoubleRangeBox(
        first: doubleValue(from: lhsBits),
        last: doubleValue(from: rhsBits)
    ))
}

@_cdecl("__kk_float_rangeTo")
public func __kk_float_rangeTo(_ lhsBits: Int, _ rhsBits: Int) -> Int {
    registerRuntimeObject(RuntimeFloatRangeBox(
        first: floatValue(from: lhsBits),
        last: floatValue(from: rhsBits)
    ))
}

@_cdecl("__kk_double_rangeUntil")
public func __kk_double_rangeUntil(_ lhsBits: Int, _ rhsBits: Int) -> Int {
    registerRuntimeObject(RuntimeDoubleRangeBox(
        first: doubleValue(from: lhsBits),
        last: doubleValue(from: rhsBits),
        endExclusive: true
    ))
}

@_cdecl("__kk_float_rangeUntil")
public func __kk_float_rangeUntil(_ lhsBits: Int, _ rhsBits: Int) -> Int {
    registerRuntimeObject(RuntimeFloatRangeBox(
        first: floatValue(from: lhsBits),
        last: floatValue(from: rhsBits),
        endExclusive: true
    ))
}

@_cdecl("__kk_double_range_contains")
public func __kk_double_range_contains(_ rangeRaw: Int, _ valueBits: Int) -> Int {
    guard let range = runtimeDoubleRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_double_range_contains")
    }
    let value = doubleValue(from: valueBits)
    guard range.first <= value else { return 0 }
    return (range.endExclusive ? value < range.last : value <= range.last) ? 1 : 0
}

@_cdecl("__kk_float_range_contains")
public func __kk_float_range_contains(_ rangeRaw: Int, _ valueBits: Int) -> Int {
    guard let range = runtimeFloatRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_float_range_contains")
    }
    let value = floatValue(from: valueBits)
    guard range.first <= value else { return 0 }
    return (range.endExclusive ? value < range.last : value <= range.last) ? 1 : 0
}

@_cdecl("__kk_double_range_isEmpty")
public func __kk_double_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeDoubleRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_double_range_isEmpty")
    }
    return (range.endExclusive ? !(range.first < range.last) : !(range.first <= range.last)) ? 1 : 0
}

@_cdecl("__kk_float_range_isEmpty")
public func __kk_float_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeFloatRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_float_range_isEmpty")
    }
    return (range.endExclusive ? !(range.first < range.last) : !(range.first <= range.last)) ? 1 : 0
}

@_cdecl("__kk_double_coerceIn_range")
public func __kk_double_coerceIn_range(
    _ valueBits: Int,
    _ rangeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let value = doubleValue(from: valueBits)
    guard let range = runtimeDoubleRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, runtimeCoerceInError(minimum: "<unknown>", maximum: "<unknown>"))
        return valueBits
    }
    guard range.first <= range.last else {
        runtimeSetThrown(
            outThrown,
            runtimeCoerceInError(minimum: "\(range.first)", maximum: "\(range.last)")
        )
        return valueBits
    }
    if value < range.first { return doubleBits(range.first) }
    if value > range.last { return doubleBits(range.last) }
    return valueBits
}

@_cdecl("__kk_float_coerceIn_range")
public func __kk_float_coerceIn_range(
    _ valueBits: Int,
    _ rangeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let value = floatValue(from: valueBits)
    guard let range = runtimeFloatRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, runtimeCoerceInError(minimum: "<unknown>", maximum: "<unknown>"))
        return valueBits
    }
    guard range.first <= range.last else {
        runtimeSetThrown(
            outThrown,
            runtimeCoerceInError(minimum: "\(range.first)", maximum: "\(range.last)")
        )
        return valueBits
    }
    if value < range.first { return floatBits(range.first) }
    if value > range.last { return floatBits(range.last) }
    return valueBits
}
