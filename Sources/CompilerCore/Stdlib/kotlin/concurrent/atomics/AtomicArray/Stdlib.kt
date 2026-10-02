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

/**
 * Returns a string representation of this array's contents, e.g. `[a, b, c]`.
 *
 * `AtomicArray` itself is runtime-backed, so its `toString` is exposed as a
 * bundled extension: bundled atomic extensions take precedence over the
 * inherited synthetic `Any.toString` member.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicArray<T>.toString(): String {
    val builder = StringBuilder()
    builder.append("[")
    var index = 0
    while (index < this.size) {
        if (index > 0) {
            builder.append(", ")
        }
        builder.append(this.loadAt(index))
        index++
    }
    builder.append("]")
    return builder.toString()
}
