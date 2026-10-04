/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/terminal/Logic.kt>.
 */

package kotlinx.coroutines.flow

public suspend fun <T> Flow<T>.any(predicate: suspend (T) -> Boolean): Boolean {
    var found = false
    collectWhile { value ->
        val matches = predicate(value)
        if (matches) found = true
        !matches
    }
    return found
}

public suspend fun <T> Flow<T>.all(predicate: suspend (T) -> Boolean): Boolean {
    var result = true
    collectWhile { value ->
        val matches = predicate(value)
        if (!matches) result = false
        matches
    }
    return result
}

public suspend fun <T> Flow<T>.none(predicate: suspend (T) -> Boolean): Boolean = !any(predicate)
