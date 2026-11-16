package kotlin.time

public interface TimeMark {
    public fun elapsedNow(): Duration
    public fun hasPassedNow(): Boolean = !elapsedNow().isNegative()
    public fun hasNotPassedNow(): Boolean = elapsedNow().isNegative()
    public operator fun plus(duration: Duration): TimeMark = OffsetTimeMark(this, duration)
    public operator fun minus(duration: Duration): TimeMark = plus(duration.negated())
}

private class OffsetTimeMark(private val mark: TimeMark, private val offset: Duration) : TimeMark {
    override fun elapsedNow(): Duration = mark.elapsedNow() + offset.negated()
    override fun plus(duration: Duration): TimeMark = OffsetTimeMark(mark, offset + duration)
}

public interface ComparableTimeMark : TimeMark, Comparable<ComparableTimeMark> {
    public override operator fun plus(duration: Duration): ComparableTimeMark
    public override operator fun minus(duration: Duration): ComparableTimeMark = plus(duration.negated())
    public operator fun minus(other: ComparableTimeMark): Duration
    public override fun compareTo(other: ComparableTimeMark): Int = minus(other).compareTo(Duration.ZERO)
}

public interface TimeSource {
    public fun markNow(): TimeMark

    public interface WithComparableMarks : TimeSource {
        public override fun markNow(): ComparableTimeMark
    }

    public object Monotonic : WithComparableMarks {
        private val origin = java.lang.System.nanoTime()

        public override fun markNow(): ValueTimeMark = ValueTimeMark(read())
        public override fun toString(): String = "TimeSource(System.nanoTime())"

        private fun read(): Long = java.lang.System.nanoTime() - origin

        @JvmInline
        public value class ValueTimeMark internal constructor(private val reading: Long) : ComparableTimeMark {
            public override fun elapsedNow(): Duration = difference(read(), reading)

            public override operator fun plus(duration: Duration): ValueTimeMark =
                ValueTimeMark(shiftReading(reading, duration))

            public override operator fun minus(duration: Duration): ValueTimeMark = plus(duration.negated())

            public override fun hasPassedNow(): Boolean = !elapsedNow().isNegative()
            public override fun hasNotPassedNow(): Boolean = elapsedNow().isNegative()

            public override operator fun minus(other: ComparableTimeMark): Duration {
                if (other !is ValueTimeMark) throw IllegalArgumentException("Time marks are from different time sources.")
                return minus(other)
            }

            public operator fun minus(other: ValueTimeMark): Duration = difference(reading, other.reading)
            public operator fun compareTo(other: ValueTimeMark): Int = reading.compareTo(other.reading)

            public override fun toString(): String = "ValueTimeMark(reading=$reading)"
        }
    }

    public companion object
}

private fun difference(end: Long, start: Long): Duration {
    if (end == start) return Duration.ZERO
    if (end == Long.MAX_VALUE || start == Long.MIN_VALUE) return Duration.INFINITE
    if (end == Long.MIN_VALUE || start == Long.MAX_VALUE) return Duration.INFINITE.negated()
    val delta = end - start
    if (((end xor start) and (end xor delta)) < 0L) {
        return (end / NANOS_PER_MILLISECOND - start / NANOS_PER_MILLISECOND).toDuration(DurationUnit.MILLISECONDS)
    }
    return delta.toDuration(DurationUnit.NANOSECONDS)
}

private fun shiftReading(reading: Long, duration: Duration): Long {
    if (reading == Long.MIN_VALUE || reading == Long.MAX_VALUE) return reading
    if (duration.isInfinite()) return duration.inWholeNanoseconds
    val offset = duration.inWholeNanoseconds
    if (offset > 0L && reading > Long.MAX_VALUE - offset) return Long.MAX_VALUE
    if (offset < 0L && reading < Long.MIN_VALUE - offset) return Long.MIN_VALUE
    return reading + offset
}
