package kotlin.sequences

@Suppress("UNCHECKED_CAST")
public inline fun <T, K, V> Sequence<T>.associate(transform: (T) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K> Sequence<T>.associateBy(keySelector: (T) -> K): Map<K, T> {
    val result = mutableMapOf<K, T>()
    for (element in this) result[keySelector(element)] = element
    return result as Map<K, T>
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K, V> Sequence<T>.associateBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result as Map<K, V>
}

@IgnorableReturnValue
public inline fun <T, K, M : MutableMap<in K, in T>> Sequence<T>.associateByTo(
    destination: M,
    keySelector: (T) -> K
): M {
    for (element in this) destination.put(keySelector(element), element)
    return destination
}

@IgnorableReturnValue
public inline fun <T, K, V, M : MutableMap<in K, in V>> Sequence<T>.associateByTo(
    destination: M,
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): M {
    for (element in this) destination.put(keySelector(element), valueTransform(element))
    return destination
}

@IgnorableReturnValue
public inline fun <T, K, V, M : MutableMap<in K, in V>> Sequence<T>.associateTo(
    destination: M,
    transform: (T) -> Pair<K, V>
): M {
    for (element in this) {
        val pair = transform(element)
        destination.put(pair.first, pair.second)
    }
    return destination
}

@SinceKotlin("1.3")
@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Sequence<K>.associateWith(valueSelector: (K) -> V): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[element] = valueSelector(element)
    return result as Map<K, V>
}

@SinceKotlin("1.3")
@IgnorableReturnValue
public inline fun <K, V, M : MutableMap<in K, in V>> Sequence<K>.associateWithTo(
    destination: M,
    valueSelector: (K) -> V
): M {
    for (element in this) destination.put(element, valueSelector(element))
    return destination
}
