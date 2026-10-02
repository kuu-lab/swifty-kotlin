package kotlin.ranges

// KSP-1316: Keep UIntRange.Companion.EMPTY source-backed. Matches Kotlin's
// `UIntRange(UInt.MAX_VALUE, UInt.MIN_VALUE)` — any first > last is empty, but
// the payload must match because `first`/`last`/`toString` observe it.
public val UIntRange.Companion.EMPTY: UIntRange
    get() = UIntRange(UInt.MAX_VALUE, UInt.MIN_VALUE)
