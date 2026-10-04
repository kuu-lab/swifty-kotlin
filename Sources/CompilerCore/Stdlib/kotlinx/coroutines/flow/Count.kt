/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/terminal/Count.kt>.
 */

package kotlinx.coroutines.flow

public suspend fun <T> Flow<T>.count(predicate: suspend (T) -> Boolean): Int {
    var count = 0
    this.collect { value ->
        if (predicate(value)) count += 1
    }
    return count
}
