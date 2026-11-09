package kotlin.ranges
class IntRange: IntProgression {
    override fun iterator(): kotlin.collections.IntIterator = null!!
    constructor(start: Int, endInclusive: Int): super(start, endInclusive, 1)
    val start: Int get() = 0
    val endInclusive: Int get() = 0
    override fun isEmpty(): Boolean = false
    operator fun contains(value: Int): Boolean = false
    override fun toString(): String = null!!
    companion object {
        val EMPTY: IntRange get() = null!!
    }
}
