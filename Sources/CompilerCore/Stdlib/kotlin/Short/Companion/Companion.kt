package kotlin

// KSP-887: Keep Short.Companion's numeric constants source-backed.
public val Short.Companion.MAX_VALUE: Short get() = 32767

public val Short.Companion.MIN_VALUE: Short get() = -32768

public val Short.Companion.SIZE_BITS: Int get() = 16

public val Short.Companion.SIZE_BYTES: Int get() = 2
