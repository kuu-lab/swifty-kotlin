package kotlin.ranges

// KSP-1316: Keep UIntRange.Companion.EMPTY source-backed.
public val UIntRange.Companion.EMPTY: UIntRange
    get() = UIntRange(1u, 0u)
