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

public open class IntProgression(public val first: Int, last: Int, public val step: Int): Iterable<Int>, kotlin.jvm.internal.markers.KMappedMarker {
    init {
        if (step == 0) throw IllegalArgumentException("Step must be non-zero.")
        if (step == Int.MIN_VALUE) throw IllegalArgumentException("Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
    }

    // Upstream computes `last` via kotlin.internal.getProgressionLastElement:
    // the bound is aligned down (or up for negative step) to the final element
    // reachable from `first`, so `(1..6 step 2).last == 5`.
    public val last: Int = getProgressionLastElement(first, last, step)

    public open fun isEmpty(): Boolean = if (step > 0) first > last else first < last
    override fun iterator(): kotlin.collections.IntIterator = IntProgressionIterator(first, last, step)
    override fun toString(): String = if (step > 0) "$first..$last step $step" else "$first downTo $last step ${-step}"
    override fun equals(other: Any?): Boolean = other is IntProgression && (isEmpty() && other.isEmpty() || first == other.first && last == other.last && step == other.step)
    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * (31 * first + last) + step
    companion object {
        public fun fromClosedRange(rangeStart: Int, rangeEnd: Int, step: Int): IntProgression = IntProgression(rangeStart, rangeEnd, step)
    }
}

// a mod b (in arithmetical sense)
private fun progressionMod(a: Int, b: Int): Int {
    val mod = a % b
    return if (mod >= 0) mod else mod + b
}

// (a - b) mod c
private fun progressionDifferenceModulo(a: Int, b: Int, c: Int): Int =
    progressionMod(progressionMod(a, c) - progressionMod(b, c), c)

private fun getProgressionLastElement(start: Int, end: Int, step: Int): Int = when {
    step > 0 -> if (start >= end) end else end - progressionDifferenceModulo(end, start, step)
    step < 0 -> if (start <= end) end else end + progressionDifferenceModulo(start, end, -step)
    else -> throw IllegalArgumentException("Step is zero.")
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
