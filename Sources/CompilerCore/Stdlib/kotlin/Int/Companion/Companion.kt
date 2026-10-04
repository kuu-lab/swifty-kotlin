package kotlin

// KSP-853: Keep Int companion constants source-backed. Int is a compiler
// primitive, so these extension properties provide the public stdlib surface
// without a runtime bridge.
public val Int.Companion.MAX_VALUE: Int get() = 2147483647

public val Int.Companion.MIN_VALUE: Int get() = -2147483648

public val Int.Companion.SIZE_BITS: Int get() = 32

public val Int.Companion.SIZE_BYTES: Int get() = 4
