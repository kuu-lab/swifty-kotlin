package kotlin.collections

public data class IndexedValue<out T>(public val index: Int, public val value: T)

internal class IndexingIterable<out T>(private val source: Iterable<T>): Iterable<IndexedValue<T>> {
    override fun iterator(): Iterator<IndexedValue<T>> = object: Iterator<IndexedValue<T>> {
        private val iterator = source.iterator()
        private var index = 0
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): IndexedValue<T> {
            if (index < 0) throw ArithmeticException("Index overflow has happened.")
            val result = IndexedValue(index, iterator.next())
            index++
            return result
        }
    }
}
