package kotlin.collections
abstract class IntIterator: Iterator<Int> {
    abstract override operator fun hasNext(): Boolean
    abstract fun nextInt(): Int
    final override operator fun next(): Int = null!!
}
