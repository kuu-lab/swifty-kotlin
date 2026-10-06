package kotlin.collections

// These overloads provide the Array surface through its existing live view.
public fun <T> Array<out T>.distinct(): List<T> = asIterable().distinct()

public fun <T> Array<out T>.toSet(): Set<T> = asIterable().toSet()

public fun <T> Array<out T>.toHashSet(): HashSet<T> = asIterable().toHashSet()

public fun <T> Array<out T>.toMutableSet(): MutableSet<T> = asIterable().toMutableSet()

public fun <T, C : MutableCollection<in T>> Array<out T>.toCollection(destination: C): C =
    asIterable().toCollection(destination)

public inline fun <T, R, C : MutableCollection<in R>> Array<out T>.mapTo(
    destination: C, transform: (T) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <T, C : MutableCollection<in T>> Array<out T>.filterTo(
    destination: C, predicate: (T) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun <T, R, C : MutableCollection<in R>> Array<out T>.flatMapTo(
    destination: C, transform: (T) -> Iterable<R>
): C {
    for (element in this) for (nested in transform(element)) destination.add(nested)
    return destination
}

@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapSequenceTo")
public inline fun <T, R, C : MutableCollection<in R>> Array<out T>.flatMapTo(
    destination: C, transform: (T) -> Sequence<R>
): C {
    for (element in this) for (nested in transform(element)) destination.add(nested)
    return destination
}

public inline fun <T> Array<out T>.partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> {
    val matching = mutableListOf<T>()
    val other = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K> Array<out T>.groupBy(keySelector: (T) -> K): Map<K, List<T>> {
    val result = mutableMapOf<K, MutableList<T>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<T>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<T>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K, V> Array<out T>.groupBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}


public inline fun <T> Array<out T>.forEachIndexed(action: (Int, T) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

// Keep typed transform calls in Kotlin; forwarding through the collection
// runtime's HOF adapter loses the Array overload's argument representation.
public infix fun <T, R> Array<out T>.zip(other: Array<out R>): List<Pair<T, R>> {
    val result = mutableListOf<Pair<T, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <T, R, V> Array<out T>.zip(other: Array<out R>, transform: (T, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <T, R> Array<out T>.zip(other: Iterable<R>): List<Pair<T, R>> {
    val result = mutableListOf<Pair<T, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <T, R, V> Array<out T>.zip(other: Iterable<R>, transform: (T, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}
