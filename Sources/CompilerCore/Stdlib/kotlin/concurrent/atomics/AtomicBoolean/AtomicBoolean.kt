/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

// The canonical atomics type is currently an alias of the runtime-backed
// kotlin.concurrent.AtomicBoolean shell. Keep the runtime entry points private and
// expose the public API as source-backed receiver declarations.
@KsSymbolName("__kk_atomic_bool_compareAndExchange")
private external fun AtomicBoolean.__kkAtomicBoolCompareAndExchange(
    expectedValue: Boolean,
    newValue: Boolean
): Boolean

@KsSymbolName("__kk_atomic_bool_exchange")
private external fun AtomicBoolean.__kkAtomicBoolExchange(newValue: Boolean): Boolean

@KsSymbolName("__kk_atomic_bool_load")
private external fun AtomicBoolean.__kkAtomicBoolLoad(): Boolean

@KsSymbolName("__kk_atomic_bool_store")
private external fun AtomicBoolean.__kkAtomicBoolStore(value: Boolean): Int

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicBoolean.compareAndExchange(expectedValue: Boolean, newValue: Boolean): Boolean =
    __kkAtomicBoolCompareAndExchange(expectedValue, newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicBoolean.exchange(newValue: Boolean): Boolean =
    __kkAtomicBoolExchange(newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicBoolean.load(): Boolean =
    __kkAtomicBoolLoad()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicBoolean.store(value: Boolean): Unit {
    __kkAtomicBoolStore(value)
}

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicBoolean.toString(): String =
    __kkAtomicBoolLoad().toString()
