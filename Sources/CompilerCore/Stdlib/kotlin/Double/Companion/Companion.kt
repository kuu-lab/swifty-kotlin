package kotlin

// KSP-833: Keep Double companion constants source-backed. Double is a compiler
// primitive, so these extension properties provide the public Companion
// surface without a runtime bridge.
public val Double.Companion.MIN_VALUE: Double get() = 4.9E-324

public val Double.Companion.MAX_VALUE: Double get() = 1.7976931348623157E308

public val Double.Companion.POSITIVE_INFINITY: Double get() = 1.0 / 0.0

public val Double.Companion.NEGATIVE_INFINITY: Double get() = -1.0 / 0.0

public val Double.Companion.NaN: Double get() = 0.0 / 0.0

public val Double.Companion.SIZE_BYTES: Int get() = 8

public val Double.Companion.SIZE_BITS: Int get() = 64
