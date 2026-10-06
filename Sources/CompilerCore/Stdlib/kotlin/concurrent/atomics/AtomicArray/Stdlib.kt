/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/AtomicArrays.common.kt>.
 */
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

/**
 * Creates an atomic reference array whose slots are copied from the given array.
 *
 * The allocation stays in the runtime box via `kk_atomic_ref_array_new`; the
 * elements are then copied in one `storeAt` at a time (the array may hold
 * nullable slots even when [T] is non-nullable at the call site).
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicArray(array: Array<T>): AtomicArray<T> {
    val result = __kkAtomicRefArrayNew<T>(array.size)
    for (index in array.indices) {
        result.storeAt(index, array[index])
    }
    return result
}

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
