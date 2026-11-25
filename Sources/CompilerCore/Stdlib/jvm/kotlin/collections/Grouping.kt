@file:kotlin.jvm.JvmName("GroupingKt")

package kotlin.collections

public interface Grouping<T, out K> {
    public fun sourceIterator(): Iterator<T>
    public fun keyOf(element: T): K
}

public fun <T, K, M : MutableMap<in K, Int>> Grouping<T, K>.eachCountTo(destination: M): M {
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val key = keyOf(iterator.next())
        destination[key] = (destination[key] ?: 0) + 1
    }
    return destination
}

public fun <T, K> Grouping<T, K>.eachCount(): Map<K, Int> =
    eachCountTo(mutableMapOf<K, Int>())
