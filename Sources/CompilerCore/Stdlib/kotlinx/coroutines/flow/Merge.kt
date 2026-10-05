/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Merge.kt>.
 */

package kotlinx.coroutines.flow

// Latest operators finish each transform sequentially, like flatMapLatest.
public fun <T, R> Flow<T>.mapLatest(transform: suspend (T) -> R): Flow<R> = map(transform)

// KUU-955: callbacks cannot cancel an in-flight transform yet. Keep collection
// streaming so downstream failures and early termination still reach upstream.
public fun <T, R> Flow<T>.transformLatest(transform: suspend FlowCollector<R>.(value: T) -> Unit): Flow<R> =
    this.transform(transform)
