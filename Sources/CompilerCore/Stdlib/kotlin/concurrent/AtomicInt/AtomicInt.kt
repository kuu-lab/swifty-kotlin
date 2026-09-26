/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/Atomics.kt>.
 */
package kotlin.concurrent

import kotlin.internal.KsSymbolName

// The scalar atomic value remains owned by the shared runtime atomic box; the
// runtime entry points stay private and the legacy receiver surface is exposed
// as source-backed members.
@KsSymbolName("__kk_atomic_int_compareAndExchange")
private external fun AtomicInt.__kkAtomicIntCompareAndExchange(
    expectedValue: Int,
    newValue: Int
): Int

@KsSymbolName("__kk_atomic_int_fetchAndAdd")
private external fun AtomicInt.__kkAtomicIntFetchAndAdd(delta: Int): Int

@KsSymbolName("__kk_atomic_int_fetchAndDecrement")
private external fun AtomicInt.__kkAtomicIntFetchAndDecrement(): Int

@KsSymbolName("__kk_atomic_int_fetchAndIncrement")
private external fun AtomicInt.__kkAtomicIntFetchAndIncrement(): Int

@KsSymbolName("__kk_atomic_int_load")
private external fun AtomicInt.__kkAtomicIntLoad(): Int

@KsSymbolName("__kk_atomic_int_store")
private external fun AtomicInt.__kkAtomicIntStore(value: Int): Unit

@SinceKotlin("1.9")
public class AtomicInt private constructor() {
    public fun compareAndExchange(expectedValue: Int, newValue: Int): Int =
        __kkAtomicIntCompareAndExchange(expectedValue, newValue)

    public fun getAndAdd(delta: Int): Int =
        __kkAtomicIntFetchAndAdd(delta)

    public fun getAndDecrement(): Int =
        __kkAtomicIntFetchAndDecrement()

    public fun getAndIncrement(): Int =
        __kkAtomicIntFetchAndIncrement()

    public override fun toString(): String =
        __kkAtomicIntLoad().toString()

    public var value: Int
        get() = __kkAtomicIntLoad()
        set(value) {
            __kkAtomicIntStore(value)
        }
}
