package kotlin.collections

public interface Grouping<T, out K> {
    public fun sourceIterator(): Iterator<T>
    public fun keyOf(element: T): K
}

public fun <T, K> Iterable<T>.groupingBy(keySelector: (T) -> K): Grouping<T, K> = null!!
