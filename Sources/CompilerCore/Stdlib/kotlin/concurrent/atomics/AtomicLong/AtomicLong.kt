/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

// The canonical atomics type is currently an alias of the runtime-backed
// kotlin.concurrent.AtomicLong shell. Keep the runtime entry points private and
// expose the public API as source-backed receiver declarations.
@KsSymbolName("__kk_atomic_long_addAndFetch")
private external fun AtomicLong.__kkAtomicLongAddAndFetch(delta: Long): Long

@KsSymbolName("__kk_atomic_long_compareAndExchange")
private external fun AtomicLong.__kkAtomicLongCompareAndExchange(
    expectedValue: Long,
    newValue: Long
): Long

@KsSymbolName("__kk_atomic_long_exchange")
private external fun AtomicLong.__kkAtomicLongExchange(newValue: Long): Long

@KsSymbolName("__kk_atomic_long_fetchAndAdd")
private external fun AtomicLong.__kkAtomicLongFetchAndAdd(delta: Long): Long

@KsSymbolName("__kk_atomic_long_fetchAndDecrement")
private external fun AtomicLong.__kkAtomicLongFetchAndDecrement(): Long

@KsSymbolName("__kk_atomic_long_fetchAndIncrement")
private external fun AtomicLong.__kkAtomicLongFetchAndIncrement(): Long

@KsSymbolName("__kk_atomic_long_load")
private external fun AtomicLong.__kkAtomicLongLoad(): Long

@KsSymbolName("__kk_atomic_long_store")
private external fun AtomicLong.__kkAtomicLongStore(value: Long): Int

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.addAndFetch(delta: Long): Long =
    __kkAtomicLongAddAndFetch(delta)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.compareAndExchange(expectedValue: Long, newValue: Long): Long =
    __kkAtomicLongCompareAndExchange(expectedValue, newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.exchange(newValue: Long): Long =
    __kkAtomicLongExchange(newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.fetchAndAdd(delta: Long): Long =
    __kkAtomicLongFetchAndAdd(delta)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.fetchAndDecrement(): Long =
    __kkAtomicLongFetchAndDecrement()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.fetchAndIncrement(): Long =
    __kkAtomicLongFetchAndIncrement()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.load(): Long =
    __kkAtomicLongLoad()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.store(value: Long): Unit {
    __kkAtomicLongStore(value)
}

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.toString(): String =
    __kkAtomicLongLoad().toString()
