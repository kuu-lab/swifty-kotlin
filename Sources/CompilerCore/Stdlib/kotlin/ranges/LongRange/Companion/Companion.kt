package kotlin.ranges

// KSP-1310: Keep LongRange.Companion.EMPTY source-backed.
public val LongRange.Companion.EMPTY: LongRange
    get() = LongRange(1L, 0L)
