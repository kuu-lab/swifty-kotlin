package kotlin.collections

public inline fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.aggregateTo(
    destination: M,
    operation: (key: K, accumulator: R?, element: T, first: Boolean) -> R
): M {
    val iterator = this.sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = this.keyOf(element)
        val accumulator = destination[key]
        destination[key] = operation(key, accumulator, element, accumulator == null && !destination.containsKey(key))
    }
    return destination
}

public inline fun <T, K, R> Grouping<T, K>.aggregate(
    operation: (key: K, accumulator: R?, element: T, first: Boolean) -> R
): Map<K, R> {
    return aggregateTo(mutableMapOf<K, R>(), operation)
}
