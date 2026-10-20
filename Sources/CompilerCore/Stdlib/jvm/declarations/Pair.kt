package kotlin
class Pair<out A, out B> {
    constructor(first: A, second: B)
    val first: A get() = null!!
    val second: B get() = null!!
    operator fun component1(): A = null!!
    operator fun component2(): B = null!!
    fun copy(first: @UnsafeVariance A = this.first, second: @UnsafeVariance B = this.second): Pair<A, B> = null!!
    override fun toString(): String = null!!
    override fun hashCode(): Int = 0
    override fun equals(other: Any?): Boolean = false
}