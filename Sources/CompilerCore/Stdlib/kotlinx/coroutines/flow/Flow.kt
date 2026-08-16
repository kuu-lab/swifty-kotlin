/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Flow.kt>.
 */

package kotlinx.coroutines.flow

// MIGRATION-FLOW-004 (KSP-499)
// Flow operators are bundled Kotlin source. The compiler/runtime keep only the
// cold-flow core (`flow`, `emit`, and `collect`) as coroutine bridges; the
// operators below compose that core instead of entering dedicated kk_flow_* ABI
// functions.

public fun <T, R> Flow<T>.map(transform: suspend (T) -> R): Flow<R> {
    val source = this
    return flow {
        source.collect { value ->
            emit(transform(value))
        }
    }
}

public fun <T> Flow<T>.filter(predicate: suspend (T) -> Boolean): Flow<T> {
    val source = this
    return flow {
        source.collect { value ->
            if (predicate(value)) {
                emit(value)
            }
        }
    }
}

public fun <T> Flow<T>.take(count: Int): Flow<T> {
    val source = this
    return flow {
        if (count <= 0) return@flow
        var emitted = 0
        source.collect { value ->
            if (emitted < count) {
                emit(value)
                emitted += 1
            }
        }
    }
}

public suspend fun <T> Flow<T>.toList(): List<T> {
    val source = this
    val result = mutableListOf<T>()
    source.collect { value -> result.add(value) }
    return result
}

public suspend fun <T> Flow<T>.first(): T {
    val source = this
    var found = false
    var result: Any? = null
    source.collect { value ->
        if (!found) {
            result = value
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Flow is empty.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public suspend fun <T> Flow<T>.single(): T {
    val source = this
    var count = 0
    var result: Any? = null
    source.collect { value ->
        count += 1
        if (count == 1) result = value
    }
    if (count == 0) throw NoSuchElementException("Flow is empty.")
    if (count > 1) throw IllegalArgumentException("Flow has more than one element.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public suspend fun <T> Flow<T>.count(): Int {
    val source = this
    var count = 0
    source.collect { count += 1 }
    return count
}

public suspend fun <T, R> Flow<T>.fold(
    initial: R,
    operation: suspend (R, T) -> R
): R {
    val source = this
    var result = initial
    source.collect { value -> result = operation(result, value) }
    return result
}

public suspend fun <T> Flow<T>.reduce(operation: suspend (T, T) -> T): T {
    val source = this
    var found = false
    var result: Any? = null
    source.collect { value ->
        if (!found) {
            result = value
            found = true
        } else {
            @Suppress("UNCHECKED_CAST")
            result = operation(result as T, value)
        }
    }
    if (!found) throw NoSuchElementException("Flow is empty.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public fun <T, R> Flow<T>.flatMapConcat(transform: suspend (T) -> Flow<R>): Flow<R> {
    val source = this
    return flow {
        source.collect { value ->
            transform(value).collect { inner -> emit(inner) }
        }
    }
}

public fun <T, R> Flow<T>.flatMapMerge(transform: suspend (T) -> Flow<R>): Flow<R> =
    flatMapConcat(transform)

public fun <T, R> Flow<T>.flatMapLatest(transform: suspend (T) -> Flow<R>): Flow<R> {
    val source = this
    return flow {
        var latest: Flow<R>? = null
        source.collect { value -> latest = transform(value) }
        val selected = latest
        if (selected != null) {
            selected.collect { value -> emit(value) }
        }
    }
}

public fun <T, R, V> Flow<T>.zip(
    other: Flow<R>,
    transform: suspend (T, R) -> V
): Flow<V> {
    val source = this
    return flow {
        val left = source.toList()
        val right = other.toList()
        val count = if (left.size < right.size) left.size else right.size
        var index = 0
        while (index < count) {
            emit(transform(left[index], right[index]))
            index += 1
        }
    }
}

public fun <T, R, V> Flow<T>.combine(
    other: Flow<R>,
    transform: suspend (T, R) -> V
): Flow<V> {
    val source = this
    return flow {
        val left = source.toList()
        val right = other.toList()
        if (left.isEmpty() || right.isEmpty()) return@flow
        val count = if (left.size > right.size) left.size else right.size
        var index = 0
        while (index < count) {
            val leftValue = left[if (index < left.size) index else left.size - 1]
            val rightValue = right[if (index < right.size) index else right.size - 1]
            emit(transform(leftValue, rightValue))
            index += 1
        }
    }
}

public fun <T> merge(vararg flows: Flow<T>): Flow<T> = flow {
    for (source in flows) {
        source.collect { value -> emit(value) }
    }
}

public fun <T> Flow<T>.debounce(timeoutMillis: Long): Flow<T> {
    val source = this
    return flow { source.collect { value -> emit(value) } }
}
