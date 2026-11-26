@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

// Consumers call this through the CollectionsKt facade
// (declarations/Grouping.kt), matching the official
// `groupingBy(Iterable, Function1): Grouping` descriptor.
public fun <T, K> Iterable<T>.groupingBy(keySelector: (T) -> K): Grouping<T, K> {
    val source = this
    return object : Grouping<T, K> {
        override fun sourceIterator(): Iterator<T> = source.iterator()
        override fun keyOf(element: T): K = keySelector(element)
    }
}
