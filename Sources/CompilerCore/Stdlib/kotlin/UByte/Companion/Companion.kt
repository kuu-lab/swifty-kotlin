package kotlin

// KSP-904: Keep UByte companion constants source-backed. UByte is a compiler
// primitive, so extension properties provide the public Companion surface
// without a runtime bridge.
public val UByte.Companion.MAX_VALUE: UByte get() = 255u

public val UByte.Companion.MIN_VALUE: UByte get() = 0u

public val UByte.Companion.SIZE_BITS: Int get() = 8

public val UByte.Companion.SIZE_BYTES: Int get() = 1
