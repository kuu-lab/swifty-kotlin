package kotlin.collections
operator fun <T> Collection<T>.plus(element: T): List<T> = null!!
operator fun <T> Iterable<T>.plus(element: T): List<T> = null!!
operator fun <T> Collection<T>.plus(elements: Iterable<T>): List<T> = null!!
operator fun <T> Iterable<T>.plus(elements: Iterable<T>): List<T> = null!!
operator fun <T> Iterable<T>.minus(element: T): List<T> = null!!
operator fun <T> Iterable<T>.minus(elements: Iterable<T>): List<T> = null!!
operator fun <T> Collection<T>.plus(elements: Array<out T>): List<T> = null!!
operator fun <T> Iterable<T>.plus(elements: Array<out T>): List<T> = null!!
operator fun <T> Iterable<T>.minus(elements: Array<out T>): List<T> = null!!
operator fun <T> Collection<T>.plus(elements: kotlin.sequences.Sequence<T>): List<T> = null!!
operator fun <T> Iterable<T>.plus(elements: kotlin.sequences.Sequence<T>): List<T> = null!!
operator fun <T> Iterable<T>.minus(elements: kotlin.sequences.Sequence<T>): List<T> = null!!
