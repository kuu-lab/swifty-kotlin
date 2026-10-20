package kotlin.ranges
class IntRange(val first: Int, val last: Int) {
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
