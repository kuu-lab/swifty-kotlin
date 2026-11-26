package kotlin.collections

// Inline bodies (not facade-bound stubs) so lambdas may non-locally return, matching kotlinc.
@Suppress("UNCHECKED_CAST")
public inline fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.foldTo(
    destination: M,
    initialValueSelector: (K, T) -> R,
    operation: (K, R, T) -> R
): M {
    val iterator = this.sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = this.keyOf(element)
        val current = destination[key]
        val accumulator = if (current == null && !destination.containsKey(key)) {
            initialValueSelector(key, element)
        } else {
            current as R
        }
        destination[key] = operation(key, accumulator, element)
    }
    return destination
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.foldTo(
    destination: M,
    initialValue: R,
    operation: (R, T) -> R
): M {
    val iterator = this.sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = this.keyOf(element)
        val current = destination[key]
        val accumulator = if (current == null && !destination.containsKey(key)) {
            initialValue
        } else {
            current as R
        }
        destination[key] = operation(accumulator, element)
    }
    return destination
}
