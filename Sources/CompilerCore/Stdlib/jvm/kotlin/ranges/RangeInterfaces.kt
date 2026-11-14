package kotlin.ranges

public interface ClosedRange<T : Comparable<T>> {
    public val start: T
    public val endInclusive: T
    public operator fun contains(value: T): Boolean = value >= start && value <= endInclusive
    public fun isEmpty(): Boolean = start > endInclusive
}

public interface OpenEndRange<T : Comparable<T>> {
    public val start: T
    public val endExclusive: T
    public operator fun contains(value: T): Boolean = value >= start && value < endExclusive
    public fun isEmpty(): Boolean = start >= endExclusive
}
