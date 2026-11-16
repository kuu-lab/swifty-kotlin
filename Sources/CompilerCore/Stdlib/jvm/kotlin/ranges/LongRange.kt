package kotlin.ranges

import kotlin.internal.getProgressionLastElement
class LongRange(first: Long, last: Long): LongProgression(first, last, 1L), ClosedRange<Long>, OpenEndRange<Long> {
    override fun iterator(): kotlin.collections.LongIterator = LongRangeIterator(first, last)

    override val start: Long get() = first
    override val endInclusive: Long get() = last
    override val endExclusive: Long
        get() {
            if (last == Long.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1L
        }
    @kotlin.jvm.JvmName("getStart") fun boxedStart(): Long? = first
    @kotlin.jvm.JvmName("getEndInclusive") fun boxedEnd(): Long? = last
    @kotlin.jvm.JvmName("getEndExclusive") fun boxedExclusiveEnd(): Long? = endExclusive
    override fun isEmpty(): Boolean = first > last
    override operator fun contains(value: Long): Boolean = value >= first && value <= last
    override fun equals(other: Any?): Boolean = other is LongRange && (isEmpty() && other.isEmpty() || first == other.first && last == other.last)
    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * first.hashCode() + last.hashCode()
    override fun toString(): String = "$first..$last"

    companion object {
        val EMPTY: LongRange = LongRange(1L, 0L)
    }
}

private class LongRangeIterator(first: Long, private val last: Long): kotlin.collections.LongIterator() {
    private var available = first <= last
    private var current = first
    override fun hasNext(): Boolean = available
    override fun nextLong(): Long {
        if (!available) throw NoSuchElementException()
        val result = current
        if (result == last) available = false else current++
        return result
    }
}

public open class LongProgression(public val first: Long, last: Long, public val step: Long): Iterable<Long>, kotlin.jvm.internal.markers.KMappedMarker {
    init {
        if (step == 0L) throw IllegalArgumentException("Step must be non-zero.")
        if (step == Long.MIN_VALUE) throw IllegalArgumentException("Step must be greater than Long.MIN_VALUE to avoid overflow on negation.")
    }

    public val last: Long = getProgressionLastElement(first, last, step)

    public open fun isEmpty(): Boolean = if (step > 0L) first > last else first < last
    override fun iterator(): kotlin.collections.LongIterator = LongProgressionIterator(first, last, step)
    override fun toString(): String = if (step > 0L) "$first..$last step $step" else "$first downTo $last step ${-step}"
    override fun equals(other: Any?): Boolean = other is LongProgression && (isEmpty() && other.isEmpty() || first == other.first && last == other.last && step == other.step)
    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * (31 * first.hashCode() + last.hashCode()) + step.hashCode()
    companion object {
        public fun fromClosedRange(rangeStart: Long, rangeEnd: Long, step: Long): LongProgression = LongProgression(rangeStart, rangeEnd, step)
    }
}

private class LongProgressionIterator(first: Long, private val last: Long, private val step: Long): kotlin.collections.LongIterator() {
    private var current = first
    private var available = if (step > 0L) first <= last else first >= last
    override fun hasNext(): Boolean = available
    override fun nextLong(): Long {
        if (!available) throw NoSuchElementException()
        val result = current
        if (result == last) available = false
        else current += step
        return result
    }
}
