package kotlin.ranges

class CharRange: Iterable<Char> {
    override fun iterator(): kotlin.collections.Iterator<Char> = null!!
    constructor(start: Char, endInclusive: Char)
    val first: Char get() = 'a'
    val last: Char get() = 'a'
    val start: Char get() = 'a'
    val endInclusive: Char get() = 'a'
    fun isEmpty(): Boolean = false
    operator fun contains(value: Char): Boolean = false
    override fun toString(): String = null!!
}
