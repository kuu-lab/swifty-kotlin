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

// Eager like the operators at the bottom of this file: calling the suspend
// transform from inside a nested collect callback miscompiles, so the inner
// flows are collected at suspend-function top level instead.
public suspend fun <T, R> Flow<T>.flatMapConcat(transform: suspend (T) -> Flow<R>): Flow<R> {
    val kept = mutableListOf<R>()
    for (value in this.toList()) {
        for (inner in transform(value).toList()) {
            kept.add(inner)
        }
    }
    return kept.asFlow()
}

public suspend fun <T, R> Flow<T>.flatMapMerge(transform: suspend (T) -> Flow<R>): Flow<R> =
    flatMapConcat(transform)

// Synchronous cold flows collect each inner flow to completion before the
// next outer value arrives, so flatMapLatest reduces to flatMapConcat here.
public suspend fun <T, R> Flow<T>.flatMapLatest(transform: suspend (T) -> Flow<R>): Flow<R> =
    flatMapConcat(transform)

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

// The operators below share the sequential-collect model: cold flows emit
// every value synchronously, so temporal/concurrent modifiers reduce to
// pass-throughs while the filtering and error operators preserve their
// value-stream semantics.

public fun <T> Flow<T>.buffer(capacity: Int): Flow<T> = this

public fun <T> Flow<T>.conflate(): Flow<T> = this

public fun <T> Flow<T>.flowOn(context: kotlin.coroutines.CoroutineContext): Flow<T> = this

public fun <T> Flow<T>.sample(periodMillis: Long): Flow<T> = this

// Stateful and error-handling operators are eager: they collect upstream at
// suspend-function top level, where suspend-function-value calls are
// well-formed, rather than inside a `flow { }` builder's collect callback
// (nested suspend-lambda capture shapes miscompile — KUU-841).

public suspend fun <T> Flow<T>.takeWhile(predicate: suspend (T) -> Boolean): Flow<T> {
    val kept = mutableListOf<T>()
    for (value in this.toList()) {
        if (!predicate(value)) break
        kept.add(value)
    }
    return kept.asFlow()
}

public suspend fun <T> Flow<T>.dropWhile(predicate: suspend (T) -> Boolean): Flow<T> {
    val kept = mutableListOf<T>()
    var dropping = true
    for (value in this.toList()) {
        if (dropping && predicate(value)) continue
        dropping = false
        kept.add(value)
    }
    return kept.asFlow()
}

public suspend fun <T> Flow<T>.onEach(action: suspend (T) -> Unit): Flow<T> {
    val kept = mutableListOf<T>()
    for (value in this.toList()) {
        action(value)
        kept.add(value)
    }
    return kept.asFlow()
}

public suspend fun <T> Flow<T>.catch(action: suspend (Throwable) -> Unit): Flow<T> {
    return try {
        this.toList().asFlow()
    } catch (e: Throwable) {
        action(e)
        emptyFlow<T>()
    }
}

public suspend fun <T> Flow<T>.onCompletion(action: suspend (cause: Throwable?) -> Unit): Flow<T> {
    var failure: Throwable? = null
    val items = try {
        this.toList()
    } catch (e: Throwable) {
        failure = e
        mutableListOf<T>()
    }
    action(failure)
    val rethrow = failure
    if (rethrow != null) throw rethrow
    return items.asFlow()
}

public suspend fun <T> Flow<T>.retry(retries: Long): Flow<T> {
    var remaining = retries
    while (true) {
        try {
            return this.toList().asFlow()
        } catch (e: Throwable) {
            if (remaining <= 0L) throw e
            remaining -= 1
        }
    }
}

public suspend fun <T> Flow<T>.retryWhen(
    predicate: suspend (cause: Throwable, attempt: Long) -> Boolean
): Flow<T> {
    var attempt: Long = 0L
    while (true) {
        try {
            return this.toList().asFlow()
        } catch (e: Throwable) {
            if (!predicate(e, attempt)) throw e
            attempt += 1
        }
    }
}
