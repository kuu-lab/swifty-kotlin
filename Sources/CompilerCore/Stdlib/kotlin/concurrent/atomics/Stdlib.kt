/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>
 * and <libraries/stdlib/src/kotlin/concurrent/atomics/AtomicArrays.common.kt>.
 */
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

// KSP-1100: canonical kotlin.concurrent.atomics nominal declarations.
// These class shells claim the residual runtime-backed synthetic surfaces and
// replace the atomics -> kotlin.concurrent typealiases; the receiver member
// migrations remain owned by the per-type sibling tickets. AtomicArray is
// declared in AtomicArray/AtomicArray.kt (KSP-1109).

/**
 * A [Boolean] value that may be updated atomically.
 */
@SinceKotlin("2.1")
@kotlin.concurrent.atomics.ExperimentalAtomicApi
public class AtomicBoolean private constructor()

/**
 * An [Int] value that may be updated atomically.
 */
@SinceKotlin("2.1")
@kotlin.concurrent.atomics.ExperimentalAtomicApi
public class AtomicInt private constructor()

/**
 * A [Long] value that may be updated atomically.
 */
@SinceKotlin("2.1")
@kotlin.concurrent.atomics.ExperimentalAtomicApi
public class AtomicLong private constructor()

/**
 * A [kotlinx.cinterop.NativePtr] value that may be updated atomically.
 */
@SinceKotlin("2.1")
@kotlin.concurrent.atomics.ExperimentalAtomicApi
public class AtomicNativePtr private constructor()

/**
 * An object reference that may be updated atomically.
 */
@SinceKotlin("2.1")
@kotlin.concurrent.atomics.ExperimentalAtomicApi
public class AtomicReference<T> private constructor()

/**
 * Creates a new [AtomicArray] of the given [size], where each element is
 * initialised to `null` of type [T].
 */
@kotlin.concurrent.atomics.ExperimentalAtomicApi
@SinceKotlin("2.1")
@KsSymbolName("kk_atomic_ref_array_new")
public external fun <T> atomicArrayOfNulls(size: Int): AtomicArray<T?>

// The runtime box is the same for `AtomicArray<T>` and `AtomicArray<T?>`;
// `is`/`as` cannot retype it, so the factory allocates with the erased
// element type directly instead of casting `atomicArrayOfNulls`' result.
@kotlin.concurrent.atomics.ExperimentalAtomicApi
@KsSymbolName("kk_atomic_ref_array_new")
private external fun <T> __kkAtomicRefArrayNew(size: Int): AtomicArray<T>

/**
 * Creates a new [AtomicArray] of the given [size], where each element is
 * initialised by calling the specified [init] function.
 */
@kotlin.concurrent.atomics.ExperimentalAtomicApi
@SinceKotlin("2.1")
public inline fun <reified T> AtomicArray(size: Int, init: (Int) -> T): AtomicArray<T> {
    val array = __kkAtomicRefArrayNew<T>(size)
    for (index in 0 until size) {
        array[index] = init(index)
    }
    return array
}
