/// Opaque runtime storage for `ClosedFloatingPointRange<Double>` values.
final class RuntimeDoubleRangeBox {
    let first: Double
    let last: Double

    init(first: Double, last: Double) {
        self.first = first
        self.last = last
    }
}

/// Opaque runtime storage for `ClosedFloatingPointRange<Float>` values.
final class RuntimeFloatRangeBox {
    let first: Float
    let last: Float

    init(first: Float, last: Float) {
        self.first = first
        self.last = last
    }
}

private func runtimeDoubleRangeBox(from raw: Int) -> RuntimeDoubleRangeBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(pointer, to: RuntimeDoubleRangeBox.self)
}

private func runtimeFloatRangeBox(from raw: Int) -> RuntimeFloatRangeBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
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
    Double(bitPattern: UInt64(bitPattern: Int64(bits)))
}

private func doubleBits(_ value: Double) -> Int {
    Int(bitPattern: UInt(value.bitPattern))
}

private func floatValue(from bits: Int) -> Float {
    Float(bitPattern: UInt32(truncatingIfNeeded: bits))
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
