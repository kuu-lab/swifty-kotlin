package kotlin.ranges

open class IntProgression: Iterable<Int> {
    constructor(first: Int, last: Int, step: Int)
    val first: Int get() = 0
    val last: Int get() = 0
    val step: Int get() = 0
    open fun isEmpty(): Boolean = false
    override fun iterator(): kotlin.collections.IntIterator = null!!
    companion object {
        fun fromClosedRange(rangeStart: Int, rangeEnd: Int, step: Int): IntProgression = null!!
    }
}
