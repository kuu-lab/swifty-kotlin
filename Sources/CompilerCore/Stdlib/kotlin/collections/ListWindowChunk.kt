package kotlin.collections

// MIGRATION-COL-009
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift

private external fun <T> __kk_list_chunked(receiver: Iterable<T>, size: Int): List<List<T>>
private external fun <T, R> __kk_list_chunked_transform(
    receiver: Iterable<T>,
    size: Int,
    transform: (List<T>) -> R
): List<R>
private external fun <T> __kk_list_windowed(
    receiver: Iterable<T>,
    size: Int,
    step: Int,
    partialWindows: Boolean
): List<List<T>>
private external fun <T, R> __kk_list_windowed_transform(
    receiver: Iterable<T>,
    size: Int,
    step: Int,
    partialWindows: Boolean,
    transform: (List<T>) -> R
): List<R>
private external fun <T, R> __kk_list_zip(
    receiver: Iterable<T>,
    other: Iterable<R>
): List<Pair<T, R>>
private external fun <T, R, V> __kk_list_zip_transform(
    receiver: Iterable<T>,
    other: Iterable<R>,
    transform: (T, R) -> V
): List<V>
private external fun <T> __kk_list_zipWithNext(receiver: Iterable<T>): List<Pair<T, T>>
private external fun <T, R> __kk_list_zipWithNextTransform(
    receiver: Iterable<T>,
    transform: (T, T) -> R
): List<R>

public fun <T> Iterable<T>.chunked(size: Int): List<List<T>> {
    require(size > 0) { "size $size must be greater than zero." }
    return __kk_list_chunked(this, size)
}

public fun <T, R> Iterable<T>.chunked(size: Int, transform: (List<T>) -> R): List<R> {
    require(size > 0) { "size $size must be greater than zero." }
    return __kk_list_chunked_transform(this, size, transform)
}

public fun <T> Iterable<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): List<List<T>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    return __kk_list_windowed(this, size, step, partialWindows)
}

public fun <T, R> Iterable<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (List<T>) -> R
): List<R> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    return __kk_list_windowed_transform(this, size, step, partialWindows, transform)
}

public fun <T> Iterable<T>.zipWithNext(): List<Pair<T, T>> =
    __kk_list_zipWithNext(this)

public inline fun <T, R> Iterable<T>.zipWithNext(transform: (T, T) -> R): List<R> {
    val iterator = iterator()
    if (!iterator.hasNext()) return emptyList()

    var previous = iterator.next()
    val result = mutableListOf<R>()
    while (iterator.hasNext()) {
        val current = iterator.next()
        result.add(transform(previous, current))
        previous = current
    }
    return result
}

// Result length equals the shorter of the two iterables, matching Kotlin
// stdlib and the Swift ABI implementation (min(lhs.count, rhs.count)).

public infix fun <T, R> Iterable<T>.zip(other: Iterable<R>): List<Pair<T, R>> {
    val first = iterator()
    val second = other.iterator()
    val result = mutableListOf<Pair<T, R>>()
    while (first.hasNext() && second.hasNext()) {
        result.add(Pair(first.next(), second.next()))
    }
    return result
}

public inline fun <T, R, V> Iterable<T>.zip(other: Iterable<R>, transform: (T, R) -> V): List<V> {
    val first = iterator()
    val second = other.iterator()
    val result = mutableListOf<V>()
    while (first.hasNext() && second.hasNext()) {
        result.add(transform(first.next(), second.next()))
    }
    return result
}

// Keep the array overload on the source path. The shared iterable bridge
// materializes both inputs instead of preserving the stdlib iterator order.
public infix fun <T, R> Iterable<T>.zip(other: Array<out R>): List<Pair<T, R>> {
    val arraySize = other.size
    val result = mutableListOf<Pair<T, R>>()
    var index = 0
    for (element in this) {
        if (index >= arraySize) break
        result.add(Pair(element, other[index]))
        index++
    }
    return result
}

public inline fun <T, R, V> Iterable<T>.zip(
    other: Array<out R>,
    transform: (a: T, b: R) -> V
): List<V> {
    val arraySize = other.size
    val result = mutableListOf<V>()
    var index = 0
    for (element in this) {
        if (index >= arraySize) break
        result.add(transform(element, other[index]))
        index++
    }
    return result
}
