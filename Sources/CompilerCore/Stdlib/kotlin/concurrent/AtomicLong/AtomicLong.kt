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
@KsSymbolName("__kk_atomic_long_compareAndExchange")
private external fun AtomicLong.__kkAtomicLongCompareAndExchange(
    expectedValue: Long,
    newValue: Long
): Long

@KsSymbolName("__kk_atomic_long_fetchAndAdd")
private external fun AtomicLong.__kkAtomicLongFetchAndAdd(delta: Long): Long

@KsSymbolName("__kk_atomic_long_fetchAndDecrement")
private external fun AtomicLong.__kkAtomicLongFetchAndDecrement(): Long

@KsSymbolName("__kk_atomic_long_fetchAndIncrement")
private external fun AtomicLong.__kkAtomicLongFetchAndIncrement(): Long

@KsSymbolName("__kk_atomic_long_load")
private external fun AtomicLong.__kkAtomicLongLoad(): Long

@KsSymbolName("__kk_atomic_long_store")
private external fun AtomicLong.__kkAtomicLongStore(value: Long): Unit

@SinceKotlin("1.9")
public class AtomicLong private constructor() {
    public fun compareAndExchange(expectedValue: Long, newValue: Long): Long =
        __kkAtomicLongCompareAndExchange(expectedValue, newValue)

    public fun getAndAdd(delta: Long): Long =
        __kkAtomicLongFetchAndAdd(delta)

    public fun getAndDecrement(): Long =
        __kkAtomicLongFetchAndDecrement()

    public fun getAndIncrement(): Long =
        __kkAtomicLongFetchAndIncrement()

    public override fun toString(): String =
        __kkAtomicLongLoad().toString()

    public var value: Long
        get() = __kkAtomicLongLoad()
        set(value) {
            __kkAtomicLongStore(value)
        }
}
