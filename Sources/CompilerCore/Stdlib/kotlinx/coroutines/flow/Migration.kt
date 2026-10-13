/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Migration.kt>.
 * Contains the subset of upstream ERROR-level deprecated Flow declarations that
 * tracked code still references; calls fail with KSWIFTK-SEMA-DEPRECATED,
 * matching kotlinc's deprecation errors.
 */

package kotlinx.coroutines.flow

private fun noImpl(): Nothing = throw UnsupportedOperationException("Not implemented, should not be called")

@Deprecated(
    level = DeprecationLevel.ERROR,
    message = "Flow analogue of 'merge' is 'flattenConcat'",
    replaceWith = ReplaceWith("flattenConcat()")
)
public fun <T> Flow<Flow<T>>.merge(): Flow<T> = noImpl()

@Deprecated(
    level = DeprecationLevel.ERROR,
    message = "Flow analogue of 'flatten' is 'flattenConcat'",
    replaceWith = ReplaceWith("flattenConcat()")
)
public fun <T> Flow<Flow<T>>.flatten(): Flow<T> = noImpl()

@Deprecated(
    level = DeprecationLevel.ERROR,
    message = "'scanReduce' was renamed to 'runningReduce' to be consistent with Kotlin standard library",
    replaceWith = ReplaceWith("runningReduce(operation)")
)
public fun <T> Flow<T>.scanReduce(
    operation: suspend (accumulator: T, value: T) -> T
): Flow<T> = runningReduce(operation)
