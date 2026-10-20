package kotlin.collections
operator fun <T> Set<T>.plus(element: T): Set<T> = null!!
operator fun <T> Set<T>.plus(elements: Iterable<T>): Set<T> = null!!
operator fun <T> Set<T>.minus(element: T): Set<T> = null!!
operator fun <T> Set<T>.minus(elements: Iterable<T>): Set<T> = null!!
operator fun <T> Set<T>.plus(elements: Array<out T>): Set<T> = null!!
operator fun <T> Set<T>.minus(elements: Array<out T>): Set<T> = null!!
operator fun <T> Set<T>.plus(elements: kotlin.sequences.Sequence<T>): Set<T> = null!!
operator fun <T> Set<T>.minus(elements: kotlin.sequences.Sequence<T>): Set<T> = null!!
