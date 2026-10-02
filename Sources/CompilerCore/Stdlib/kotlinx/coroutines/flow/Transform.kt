/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Transform.kt>.
 */

package kotlinx.coroutines.flow

public fun <T> Flow<T>.filterNot(predicate: suspend (T) -> Boolean): Flow<T> {
    val source = this
    return flow {
        source.collect { value ->
            if (!predicate(value)) emit(value)
        }
    }
}

public fun <T : Any> Flow<T?>.filterNotNull(): Flow<T> {
    val source = this
    return flow {
        source.collect { value ->
            if (value != null) emit(value)
        }
    }
}

public inline fun <reified R> Flow<*>.filterIsInstance(): Flow<R> {
    val source = this
    return flow {
        source.collect { value ->
            if (value is R) emit(value)
        }
    }
}

public fun <T, R : Any> Flow<T>.mapNotNull(transform: suspend (T) -> R?): Flow<R> {
    val source = this
    return flow {
        source.collect { value ->
            val result = transform(value)
            if (result != null) emit(result)
        }
    }
}

public fun <T> Flow<T>.onEach(action: suspend (T) -> Unit): Flow<T> {
    val source = this
    return flow {
        source.collect { value ->
            action(value)
            emit(value)
        }
    }
}

public fun <T> Flow<T>.drop(count: Int): Flow<T> {
    require(count >= 0) { "Drop count must be non-negative" }
    val source = this
    return flow {
        var skipped = 0
        source.collect { value ->
            if (skipped < count) skipped += 1 else emit(value)
        }
    }
}

public fun <T> Flow<T>.dropWhile(predicate: suspend (T) -> Boolean): Flow<T> {
    val source = this
    return flow {
        var dropping = true
        source.collect { value ->
            if (!dropping || !predicate(value)) {
                dropping = false
                emit(value)
            }
        }
    }
}

public fun <T> Flow<T>.takeWhile(predicate: suspend (T) -> Boolean): Flow<T> {
    val source = this
    return flow {
        val collector = SendingCollector<T> { value -> emit(value) }
        try {
            source.collect { value ->
                if (!predicate(value)) throw AbortFlowException(collector)
                collector.emit(value)
            }
        } catch (e: AbortFlowException) {
            if (e.owner !== collector) throw e
        }
    }
}

public fun <T> Flow<T>.withIndex(): Flow<kotlin.collections.IndexedValue<T>> {
    val source = this
    return flow {
        var index = 0
        source.collect { value ->
            if (index < 0) throw ArithmeticException("Index overflow has happened")
            emit(kotlin.collections.IndexedValue(index, value))
            index += 1
        }
    }
}

public suspend fun <T> Flow<T>.collectIndexed(action: suspend (index: Int, value: T) -> Unit) {
    var index = 0
    this.collect { value ->
        if (index < 0) throw ArithmeticException("Index overflow has happened")
        action(index, value)
        index += 1
    }
}
