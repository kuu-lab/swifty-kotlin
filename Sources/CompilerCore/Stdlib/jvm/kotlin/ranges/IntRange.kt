package kotlin.ranges
class IntRange(first: Int, last: Int): IntProgression(first, last, 1), kotlin.jvm.internal.markers.KMappedMarker {
    override fun iterator(): kotlin.collections.IntIterator = IntRangeIterator(first, last)

    val start: Int get() = first
    val endInclusive: Int get() = last
    @kotlin.jvm.JvmName("getStart") fun boxedStart(): Int? = first
    @kotlin.jvm.JvmName("getEndInclusive") fun boxedEnd(): Int? = last
    override fun isEmpty(): Boolean = first > last
    operator fun contains(value: Int): Boolean = value >= first && value <= last
    override fun equals(other: Any?): Boolean = other is IntRange && (isEmpty() && other.isEmpty() || first == other.first && last == other.last)
    override fun hashCode(): Int = if (isEmpty()) -1 else first * 31 + last
    override fun toString(): String = "$first..$last"

    // KUU-2834: Keep the JVM range companion surface available to consumers.
    companion object {
        val EMPTY: IntRange = IntRange(1, 0)
    }
}

private class IntRangeIterator(first: Int, private val last: Int): kotlin.collections.IntIterator() {
    private var available = first <= last
    private var current = first
    override fun hasNext(): Boolean = available
    override fun nextInt(): Int {
        if (!available) throw NoSuchElementException()
        val result = current
        if (result == last) available = false else current++
        return result
    }
}

public open class IntProgression(public val first: Int, public val last: Int, public val step: Int): Iterable<Int>, kotlin.jvm.internal.markers.KMappedMarker {
    public open fun isEmpty(): Boolean = if (step > 0) first > last else first < last
    override fun iterator(): kotlin.collections.IntIterator = IntProgressionIterator(first, last, step)
    override fun toString(): String = if (step > 0) "$first..$last step $step" else "$first downTo $last step ${-step}"
    override fun equals(other: Any?): Boolean = other is IntProgression && (isEmpty() && other.isEmpty() || first == other.first && last == other.last && step == other.step)
    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * (31 * first + last) + step
    companion object {
        public fun fromClosedRange(rangeStart: Int, rangeEnd: Int, step: Int): IntProgression = IntProgression(rangeStart, rangeEnd, step)
    }
}

private class IntProgressionIterator(first: Int, private val last: Int, private val step: Int): kotlin.collections.IntIterator() {
    private var current = first
    private var available = if (step > 0) first <= last else first >= last
    override fun hasNext(): Boolean = available
    override fun nextInt(): Int {
        if (!available) throw NoSuchElementException()
        val result = current
        if (result == last) available = false
        else {
            val next = current + step
            if (step > 0) { if (next > last || next < result) available = false else current = next }
            else { if (next < last || next > result) available = false else current = next }
        }
        return result
    }
}
