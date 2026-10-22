package kotlin.ranges
class IntRange(val first: Int, val last: Int): Iterable<Int>, kotlin.jvm.internal.markers.KMappedMarker {
    override fun iterator(): kotlin.collections.IntIterator = IntRangeIterator(first, last)

    val start: Int get() = first
    val endInclusive: Int get() = last
    @kotlin.jvm.JvmName("getStart") fun boxedStart(): Int? = first
    @kotlin.jvm.JvmName("getEndInclusive") fun boxedEnd(): Int? = last
    fun isEmpty(): Boolean = first > last
    operator fun contains(value: Int): Boolean = value >= first && value <= last
    override fun equals(other: Any?): Boolean = other is IntRange && (isEmpty() && other.isEmpty() || first == other.first && last == other.last)
    override fun hashCode(): Int = if (isEmpty()) -1 else first * 31 + last
    override fun toString(): String = "$first..$last"
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
