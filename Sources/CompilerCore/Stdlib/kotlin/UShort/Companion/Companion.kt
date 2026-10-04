package kotlin

// KSP-913: Keep UShort companion constants source-backed. UShort is a
// compiler primitive, so extension properties provide the public Companion
// surface without a runtime bridge.
public val UShort.Companion.MAX_VALUE: UShort get() = 65535u

public val UShort.Companion.MIN_VALUE: UShort get() = 0u

public val UShort.Companion.SIZE_BITS: Int get() = 16

public val UShort.Companion.SIZE_BYTES: Int get() = 2
