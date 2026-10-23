package kotlin.ranges
class IntRange: Iterable<Int> {
    override fun iterator(): kotlin.collections.IntIterator = null!!
    constructor(start: Int, endInclusive: Int)
    val first: Int get() = 0
    val last: Int get() = 0
    val start: Int get() = 0
    val endInclusive: Int get() = 0
    fun isEmpty(): Boolean = false
    operator fun contains(value: Int): Boolean = false
    override fun toString(): String = null!!
    companion object {
        val EMPTY: IntRange get() = null!!
    }
}
