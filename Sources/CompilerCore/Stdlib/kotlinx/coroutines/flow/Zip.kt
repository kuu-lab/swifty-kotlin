/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Zip.kt>
 * and <kotlinx-coroutines-core/common/src/flow/Migration.kt>.
 */

package kotlinx.coroutines.flow

// Match the existing two-flow combine's sequential snapshot model: emit
// indexed values, retaining each shorter flow's last value until all end.
public fun <T, R> combine(vararg flows: Flow<T>, transform: suspend (Array<T>) -> R): Flow<R> =
    combine(flows.toList(), transform)

public fun <T, R> combine(flows: Iterable<Flow<T>>, transform: suspend (Array<T>) -> R): Flow<R> = flow {
    val sources = mutableListOf<List<T>>()
    var count = 0
    for (source in flows) {
        val values = source.toList()
        if (values.isEmpty()) return@flow
        sources.add(values)
        if (values.size > count) count = values.size
    }
    var index = 0
    while (index < count) {
        val values = mutableListOf<T>()
        for (source in sources) {
            values.add(source[if (index < source.size) index else source.size - 1])
        }
        emit(transform(values.toTypedArray()))
        index += 1
    }
}

public fun <T1, T2, R> combine(
    flow: Flow<T1>, flow2: Flow<T2>, transform: suspend (T1, T2) -> R
): Flow<R> = flow.combine(flow2, transform)

@Suppress("UNCHECKED_CAST")
public fun <T1, T2, T3, R> combine(
    flow: Flow<T1>, flow2: Flow<T2>, flow3: Flow<T3>, transform: suspend (T1, T2, T3) -> R
): Flow<R> = combine<Any?, R>(flow, flow2, flow3) { values ->
    transform(values[0] as T1, values[1] as T2, values[2] as T3)
}

@Suppress("UNCHECKED_CAST")
public fun <T1, T2, T3, T4, R> combine(
    flow: Flow<T1>, flow2: Flow<T2>, flow3: Flow<T3>, flow4: Flow<T4>,
    transform: suspend (T1, T2, T3, T4) -> R
): Flow<R> = combine<Any?, R>(flow, flow2, flow3, flow4) { values ->
    transform(values[0] as T1, values[1] as T2, values[2] as T3, values[3] as T4)
}

@Suppress("UNCHECKED_CAST")
public fun <T1, T2, T3, T4, T5, R> combine(
    flow: Flow<T1>, flow2: Flow<T2>, flow3: Flow<T3>, flow4: Flow<T4>, flow5: Flow<T5>,
    transform: suspend (T1, T2, T3, T4, T5) -> R
): Flow<R> = combine<Any?, R>(flow, flow2, flow3, flow4, flow5) { values ->
    transform(values[0] as T1, values[1] as T2, values[2] as T3, values[3] as T4, values[4] as T5)
}

public fun <T1, T2, R> Flow<T1>.combineLatest(other: Flow<T2>, transform: suspend (T1, T2) -> R): Flow<R> =
    combine(other, transform)

public fun <T1, T2, T3, R> Flow<T1>.combineLatest(
    other: Flow<T2>, other2: Flow<T3>, transform: suspend (T1, T2, T3) -> R
): Flow<R> = combine(this, other, other2, transform)

public fun <T1, T2, T3, T4, R> Flow<T1>.combineLatest(
    other: Flow<T2>, other2: Flow<T3>, other3: Flow<T4>, transform: suspend (T1, T2, T3, T4) -> R
): Flow<R> = combine(this, other, other2, other3, transform)

public fun <T1, T2, T3, T4, T5, R> Flow<T1>.combineLatest(
    other: Flow<T2>, other2: Flow<T3>, other3: Flow<T4>, other4: Flow<T5>,
    transform: suspend (T1, T2, T3, T4, T5) -> R
): Flow<R> = combine(this, other, other2, other3, other4, transform)
