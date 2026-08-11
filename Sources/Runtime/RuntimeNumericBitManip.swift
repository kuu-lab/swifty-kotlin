
// Bit-manipulation runtime functions (STDLIB-BIT-007).
//
// Split out from `RuntimeNumericCompat.swift`.

// MARK: - STDLIB-BIT-007: Additional bit manipulation functions

// KSP-642: rotateLeft / rotateRight are implemented in bundled Kotlin source
// (`Stdlib/kotlin/Numbers.kt`) using shl / ushr / or, so no runtime entrypoint
// is needed for them.

@_cdecl("kk_int_highestOneBit")
public func kk_int_highestOneBit(_ value: Int) -> Int {
    let truncated = Int32(truncatingIfNeeded: value)
    if truncated == 0 { return 0 }
    return Int(1 << (31 - truncated.leadingZeroBitCount))
}

@_cdecl("kk_int_lowestOneBit")
public func kk_int_lowestOneBit(_ value: Int) -> Int {
    let bits = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
    if bits == 0 { return 0 }
    return Int(Int32(bitPattern: bits & (0 &- bits)))
}

@_cdecl("kk_int_takeHighestOneBit")
public func kk_int_takeHighestOneBit(_ value: Int) -> Int {
    let truncated = Int32(truncatingIfNeeded: value)
    if truncated == 0 { return 0 }
    let shift = 31 - truncated.leadingZeroBitCount
    let mask = Int32(bitPattern: UInt32(0xFFFF_FFFF) << shift)
    return Int(truncated & mask)
}

@_cdecl("kk_int_takeLowestOneBit")
public func kk_int_takeLowestOneBit(_ value: Int) -> Int {
    kk_int_lowestOneBit(value)
}

// Long bit manipulation functions (64-bit)

@_cdecl("kk_long_highestOneBit")
public func kk_long_highestOneBit(_ value: Int) -> Int {
    if value == 0 { return 0 }
    return 1 << (63 - value.leadingZeroBitCount)
}

@_cdecl("kk_long_lowestOneBit")
public func kk_long_lowestOneBit(_ value: Int) -> Int {
    let bits = UInt(bitPattern: value)
    if bits == 0 { return 0 }
    return Int(bitPattern: bits & (0 &- bits))
}

@_cdecl("kk_long_takeHighestOneBit")
public func kk_long_takeHighestOneBit(_ value: Int) -> Int {
    if value == 0 { return 0 }
    let shift = 63 - value.leadingZeroBitCount
    return value & (~0 << shift)
}

@_cdecl("kk_long_takeLowestOneBit")
public func kk_long_takeLowestOneBit(_ value: Int) -> Int {
    kk_long_lowestOneBit(value)
}

// Unsigned coercion helpers compare the raw intptr_t payload as UInt so the
// runtime preserves the bit pattern for UByte/UShort/UInt/ULong values.
@inline(__always)
private func runtimeUnsignedCoerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    let v = UInt(bitPattern: value)
    let lo = UInt(bitPattern: minimum)
    let hi = UInt(bitPattern: maximum)
    precondition(!(lo > hi), "Cannot coerce value to an empty range: maximum \(hi) is less than minimum \(lo).")
    if v < lo { return minimum }
    if v > hi { return maximum }
    return value
}

@inline(__always)
private func runtimeUnsignedCoerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    UInt(bitPattern: value) < UInt(bitPattern: minimum) ? minimum : value
}

@inline(__always)
private func runtimeUnsignedCoerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    UInt(bitPattern: value) > UInt(bitPattern: maximum) ? maximum : value
}

@_cdecl("kk_ubyte_coerceIn")
public func kk_ubyte_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_ubyte_coerceAtLeast")
public func kk_ubyte_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_ubyte_coerceAtMost")
public func kk_ubyte_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}

@_cdecl("kk_ushort_coerceIn")
public func kk_ushort_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_ushort_coerceAtLeast")
public func kk_ushort_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_ushort_coerceAtMost")
public func kk_ushort_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}

@_cdecl("kk_uint_coerceIn")
public func kk_uint_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_uint_coerceAtLeast")
public func kk_uint_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_uint_coerceAtMost")
public func kk_uint_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}

@_cdecl("kk_ulong_coerceIn")
public func kk_ulong_coerceIn(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceIn(value, minimum, maximum)
}

@_cdecl("kk_ulong_coerceAtLeast")
public func kk_ulong_coerceAtLeast(_ value: Int, _ minimum: Int) -> Int {
    runtimeUnsignedCoerceAtLeast(value, minimum)
}

@_cdecl("kk_ulong_coerceAtMost")
public func kk_ulong_coerceAtMost(_ value: Int, _ maximum: Int) -> Int {
    runtimeUnsignedCoerceAtMost(value, maximum)
}
