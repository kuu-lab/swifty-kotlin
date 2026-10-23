package kotlin.ranges

class LongRange: Iterable<Long> {
    override fun iterator(): kotlin.collections.Iterator<Long> = null!!
    constructor(start: Long, endInclusive: Long)
    val first: Long get() = 0L
    val last: Long get() = 0L
    val start: Long get() = 0L
    val endInclusive: Long get() = 0L
    fun isEmpty(): Boolean = false
    operator fun contains(value: Long): Boolean = false
    override fun toString(): String = null!!
}
