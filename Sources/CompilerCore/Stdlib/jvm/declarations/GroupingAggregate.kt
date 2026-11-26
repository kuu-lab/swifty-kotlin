package kotlin.collections

public inline fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.aggregateTo(
    destination: M,
    operation: (key: K, accumulator: R?, element: T, first: Boolean) -> R
): M {
    // A concrete destination type (e.g. LinkedHashMap) is not accepted by the
    // JVM index-assignment lowering, so go through the MutableMap interface.
    val map: MutableMap<in K, R> = destination
    val iterator = this.sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = this.keyOf(element)
        val accumulator = map[key]
        map[key] = operation(key, accumulator, element, accumulator == null && !map.containsKey(key))
    }
    return destination
}

public inline fun <T, K, R> Grouping<T, K>.aggregate(
    operation: (key: K, accumulator: R?, element: T, first: Boolean) -> R
): Map<K, R> {
    return aggregateTo(mutableMapOf<K, R>(), operation)
}
