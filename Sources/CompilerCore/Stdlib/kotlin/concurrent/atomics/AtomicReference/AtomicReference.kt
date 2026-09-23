/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

// The canonical atomics type is currently an alias of the runtime-backed
// kotlin.concurrent.AtomicReference shell. Keep the runtime entry points
// private and expose the public API as source-backed receiver declarations.
@KsSymbolName("__kk_atomic_ref_compareAndExchange")
private external fun <T> AtomicReference<T>.__kkAtomicRefCompareAndExchange(
    expectedValue: T,
    newValue: T
): T

@KsSymbolName("__kk_atomic_ref_exchange")
private external fun <T> AtomicReference<T>.__kkAtomicRefExchange(newValue: T): T

@KsSymbolName("__kk_atomic_ref_load")
private external fun <T> AtomicReference<T>.__kkAtomicRefLoad(): T

@KsSymbolName("__kk_atomic_ref_store")
private external fun <T> AtomicReference<T>.__kkAtomicRefStore(value: T): Unit

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference<T>.compareAndExchange(expectedValue: T, newValue: T): T =
    __kkAtomicRefCompareAndExchange(expectedValue, newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference<T>.exchange(newValue: T): T =
    __kkAtomicRefExchange(newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference<T>.getAndSet(newValue: T): T =
    exchange(newValue)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference<T>.load(): T =
    __kkAtomicRefLoad()

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference<T>.store(value: T): Unit {
    __kkAtomicRefStore(value)
}

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference<T>.toString(): String =
    __kkAtomicRefLoad().toString()

// `var value: T` is owned by the runtime-backed class shell. A bundled
// extension property cannot name the class type parameter, and a
// star-projected `AtomicReference<*>` variant would shadow the member's
// T-typed getter for atomics callers, so the member stays the source of
// truth for value reads and writes.
