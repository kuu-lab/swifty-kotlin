package kotlin.ranges

// KSP-1297: Keep CharRange.Companion.EMPTY source-backed.
public val CharRange.Companion.EMPTY: CharRange
    get() = CharRange(1.toChar(), 0.toChar())
