/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/terminal/Reduce.kt>.
 */

package kotlinx.coroutines.flow

public suspend fun <T> Flow<T>.firstOrNull(): T? {
    var result: T? = null
    collectWhile { value ->
        result = value
        false
    }
    return result
}

public suspend fun <T> Flow<T>.firstOrNull(predicate: suspend (T) -> Boolean): T? {
    var result: T? = null
    collectWhile { value ->
        if (predicate(value)) {
            result = value
            false
        } else {
            true
        }
    }
    return result
}

public suspend fun <T> Flow<T>.last(): T {
    var found = false
    var result: Any? = null
    this.collect { value ->
        result = value
        found = true
    }
    if (!found) throw NoSuchElementException("Flow is empty.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public suspend fun <T> Flow<T>.lastOrNull(): T? {
    var result: T? = null
    this.collect { value -> result = value }
    return result
}

public suspend fun <T> Flow<T>.singleOrNull(): T? {
    var found = false
    var result: T? = null
    collectWhile { value ->
        if (!found) {
            result = value
            found = true
            true
        } else {
            result = null
            false
        }
    }
    return result
}
