/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/AtomicArrays.common.kt>.
 */
package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

/**
 * Creates an atomic long array of the requested size, initialized to zero.
 *
 * The allocation remains in the runtime box; this declaration provides the
 * source-backed stdlib entry point for the existing runtime ABI.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
@KsSymbolName("kk_atomic_long_array_create")
public external fun AtomicLongArray(size: Int): AtomicLongArray

/**
 * Creates an atomic long array from a copy of the supplied array.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLongArray(array: LongArray): AtomicLongArray {
    val result = AtomicLongArray(array.size)
    var index = 0
    while (index < array.size) {
        result[index] = array[index]
        index++
    }
    return result
}

/**
 * Creates a new [AtomicLongArray] of the given [size], where each element is
 * initialised by calling the [init] function with its index.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public inline fun AtomicLongArray(size: Int, init: (Int) -> Long): AtomicLongArray {
    val result = AtomicLongArray(size)
    for (index in 0 until size) {
        result[index] = init(index)
    }
    return result
}
