/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/terminal/Collection.kt>.
 */

package kotlinx.coroutines.flow

public suspend fun <T, C : MutableCollection<in T>> Flow<T>.toCollection(destination: C): C {
    this.collect { value -> destination.add(value) }
    return destination
}

public suspend fun <T> Flow<T>.toSet(destination: MutableSet<T> = linkedSetOf<T>()): Set<T> =
    toCollection(destination)
