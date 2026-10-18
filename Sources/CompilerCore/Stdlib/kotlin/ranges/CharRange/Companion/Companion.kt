package kotlin.ranges

public val CharRange.Companion.EMPTY: CharRange
    get() = CharRange(1.toChar(), 0.toChar())
