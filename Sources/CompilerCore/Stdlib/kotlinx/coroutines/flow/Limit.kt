/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Delay.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.inWholeMilliseconds
import kotlin.time.toDuration

// KSP-1581: no ticker in the sequential cold-flow model; sample emits only
// the last upstream value on completion, including a null value.
@Suppress("UNCHECKED_CAST")
public fun <T> Flow<T>.sample(periodMillis: Long): Flow<T> {
    require(periodMillis > 0L) { "Sample period should be positive" }
    val source = this
    return flow {
        var seen = false
        var last: Any? = null
        source.collect { value ->
            seen = true
            last = value
        }
        if (seen) emit(last as T)
    }
}

public fun <T> Flow<T>.sample(period: Duration): Flow<T> {
    require(period > 0L.toDuration(DurationUnit.MILLISECONDS)) { "Sample period should be positive" }
    val millis = period.inWholeMilliseconds
    return sample(if (millis > 0L) millis else 1L)
}
