package kotlin.ranges

// KSP-1304: Keep IntRange.Companion.EMPTY source-backed.
public val IntRange.Companion.EMPTY: IntRange
    get() = IntRange(1, 0)
