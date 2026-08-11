
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
