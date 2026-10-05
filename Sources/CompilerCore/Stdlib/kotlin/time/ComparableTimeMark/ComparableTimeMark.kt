package kotlin.time

// KSP-1482: ComparableTimeMark's source-aware member contract.
public interface ComparableTimeMark : TimeMark, Comparable<ComparableTimeMark> {
    public override operator fun plus(duration: Duration): ComparableTimeMark

    public override operator fun minus(duration: Duration): ComparableTimeMark = plus(-duration)

    public operator fun minus(other: ComparableTimeMark): Duration

    public override operator fun compareTo(other: ComparableTimeMark): Int =
        (this - other).compareTo(Duration.ZERO)

    public override fun equals(other: Any?): Boolean

    public override fun hashCode(): Int
}
