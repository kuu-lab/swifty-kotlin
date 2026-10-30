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

class Triple<out A, out B, out C> {
    constructor(first: A, second: B, third: C)
    val first: A get() = null!!
    val second: B get() = null!!
    val third: C get() = null!!
    operator fun component1(): A = null!!
    operator fun component2(): B = null!!
    operator fun component3(): C = null!!
    fun copy(first: @UnsafeVariance A = this.first, second: @UnsafeVariance B = this.second, third: @UnsafeVariance C = this.third): Triple<A, B, C> = null!!
    fun toList(): List<Any?> = null!!
    override fun toString(): String = null!!
    override fun hashCode(): Int = 0
    override fun equals(other: Any?): Boolean = false
}
