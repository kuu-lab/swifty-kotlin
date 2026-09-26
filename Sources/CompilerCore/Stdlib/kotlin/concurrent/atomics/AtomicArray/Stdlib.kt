/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/AtomicArrays.common.kt>.
 */
package kotlin.concurrent.atomics

/**
 * Creates an atomic reference array whose slots are copied from the given array.
 *
 * The allocation stays in the runtime box via the existing `atomicArrayOf`
 * bridge (`kk_atomic_ref_array_of` copies the elements into a fresh atomic
 * box); this declaration provides the source-backed `AtomicArray(array)`
 * entry point.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicArray(array: Array<T>): AtomicArray<T> =
    atomicArrayOf(*array)
