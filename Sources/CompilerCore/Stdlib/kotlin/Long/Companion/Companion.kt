package kotlin

// KSP-860: Keep Long.Companion's numeric constants in bundled Kotlin source.
private fun ksp860LongMaxValue(): Long = 9223372036854775807L
private fun ksp860LongMinValue(): Long = 0x8000000000000000L
private fun ksp860LongSizeBits(): Int = 64
private fun ksp860LongSizeBytes(): Int = 8

public val Long.Companion.MAX_VALUE: Long get() = ksp860LongMaxValue()
public val Long.Companion.MIN_VALUE: Long get() = ksp860LongMinValue()
public val Long.Companion.SIZE_BITS: Int get() = ksp860LongSizeBits()
public val Long.Companion.SIZE_BYTES: Int get() = ksp860LongSizeBytes()
