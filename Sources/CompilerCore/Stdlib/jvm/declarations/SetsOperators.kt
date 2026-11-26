package kotlin.collections
@kotlin.internal.InlineOnly
inline fun <T> Set<T>.plusElement(element: T): Set<T> = plus(element)
@kotlin.internal.InlineOnly
inline fun <T> Set<T>.minusElement(element: T): Set<T> = minus(element)
operator fun <T> Set<T>.plus(element: T): Set<T> = null!!
operator fun <T> Set<T>.plus(elements: Iterable<T>): Set<T> = null!!
operator fun <T> Set<T>.minus(element: T): Set<T> = null!!
operator fun <T> Set<T>.minus(elements: Iterable<T>): Set<T> = null!!
operator fun <T> Set<T>.plus(elements: Array<out T>): Set<T> = null!!
operator fun <T> Set<T>.minus(elements: Array<out T>): Set<T> = null!!
operator fun <T> Set<T>.plus(elements: kotlin.sequences.Sequence<T>): Set<T> = null!!
operator fun <T> Set<T>.minus(elements: kotlin.sequences.Sequence<T>): Set<T> = null!!
