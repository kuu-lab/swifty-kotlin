/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

// The canonical atomics type is currently an alias of the runtime-backed
// kotlin.concurrent.AtomicInt shell. Keep the runtime entry points private and
// expose the public API as source-backed receiver declarations.
@KsSymbolName("__kk_atomic_int_addAndFetch")
private external fun AtomicInt.__kkAtomicIntAddAndFetch(delta: Int): Int

@KsSymbolName("__kk_atomic_int_compareAndExchange")
private external fun AtomicInt.__kkAtomicIntCompareAndExchange(
    expectedValue: Int,
    newValue: Int
): Int

@KsSymbolName("__kk_atomic_int_exchange")
private external fun AtomicInt.__kkAtomicIntExchange(newValue: Int): Int

@KsSymbolName("__kk_atomic_int_fetchAndAdd")
private external fun AtomicInt.__kkAtomicIntFetchAndAdd(delta: Int): Int

@KsSymbolName("__kk_atomic_int_fetchAndDecrement")
private external fun AtomicInt.__kkAtomicIntFetchAndDecrement(): Int

@KsSymbolName("__kk_atomic_int_fetchAndIncrement")
private external fun AtomicInt.__kkAtomicIntFetchAndIncrement(): Int

@KsSymbolName("__kk_atomic_int_load")
private external fun AtomicInt.__kkAtomicIntLoad(): Int

@KsSymbolName("__kk_atomic_int_store")
private external fun AtomicInt.__kkAtomicIntStore(value: Int): Int

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.addAndFetch(delta: Int): Int =
    __kkAtomicIntAddAndFetch(delta)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.compareAndExchange(expectedValue: Int, newValue: Int): Int =
    __kkAtomicIntCompareAndExchange(expectedValue, newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.exchange(newValue: Int): Int =
    __kkAtomicIntExchange(newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.getAndAdd(delta: Int): Int =
    __kkAtomicIntFetchAndAdd(delta)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.getAndDecrement(): Int =
    __kkAtomicIntFetchAndDecrement()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.getAndIncrement(): Int =
    __kkAtomicIntFetchAndIncrement()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.load(): Int =
    __kkAtomicIntLoad()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.store(value: Int): Unit {
    __kkAtomicIntStore(value)
}

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt.toString(): String =
    __kkAtomicIntLoad().toString()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public val AtomicInt.value: Int
    get() = __kkAtomicIntLoad()
