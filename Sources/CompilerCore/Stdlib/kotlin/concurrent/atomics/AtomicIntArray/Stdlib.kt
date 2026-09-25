/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/AtomicArrays.common.kt>.
 */
package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

/**
 * Creates an atomic integer array of the requested size, initialized to zero.
 *
 * The allocation remains in the runtime box; this declaration provides the
 * source-backed stdlib entry point for the existing runtime ABI.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
@KsSymbolName("kk_atomic_int_array_create")
public external fun AtomicIntArray(size: Int): AtomicIntArray

/**
 * Creates an atomic integer array from a copy of the supplied array.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicIntArray(array: IntArray): AtomicIntArray {
    val result = AtomicIntArray(array.size)
    var index = 0
    while (index < array.size) {
        result[index] = array[index]
        index++
    }
    return result
}

/**
 * Creates a new [AtomicIntArray] of the given [size], where each element is
 * initialised by calling the [init] function with its index.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public inline fun AtomicIntArray(size: Int, init: (Int) -> Int): AtomicIntArray {
    val result = AtomicIntArray(size)
    for (index in 0 until size) {
        result[index] = init(index)
    }
    return result
}
