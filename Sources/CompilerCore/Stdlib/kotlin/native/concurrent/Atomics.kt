/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Atomics.kt>.
 */

@file:OptIn(ExperimentalForeignApi::class)
@file:Suppress("DEPRECATION_ERROR")

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.NativePtr

// KSP-1221: The legacy native AtomicInt receiver surface is source-backed
// while its storage remains owned by the shared runtime atomic box. Keep the
// ABI-only operations private and expose the Kotlin/Native API as extensions
// on the KSP-1220 synthetic nominal anchor.
@KsSymbolName("__kk_atomic_int_load")
private external fun AtomicInt.__kkAtomicIntLoad(): Int

@KsSymbolName("__kk_atomic_int_store")
private external fun AtomicInt.__kkAtomicIntStore(value: Int): Unit

@KsSymbolName("__kk_atomic_int_compareAndExchange")
private external fun AtomicInt.__kkAtomicIntCompareAndExchange(expected: Int, newValue: Int): Int

@KsSymbolName("__kk_atomic_int_fetchAndAdd")
private external fun AtomicInt.__kkAtomicIntFetchAndAdd(delta: Int): Int

@KsSymbolName("__kk_atomic_int_fetchAndIncrement")
private external fun AtomicInt.__kkAtomicIntFetchAndIncrement(): Int

@KsSymbolName("__kk_atomic_int_fetchAndDecrement")
private external fun AtomicInt.__kkAtomicIntFetchAndDecrement(): Int

@KsSymbolName("__kk_atomic_int_incrementAndFetch")
private external fun AtomicInt.__kkAtomicIntIncrementAndFetch(): Int

@KsSymbolName("__kk_atomic_int_decrementAndFetch")
private external fun AtomicInt.__kkAtomicIntDecrementAndFetch(): Int

/** The atomically stored value of the legacy native atomic wrapper. */
public var AtomicInt.value: Int
    get() = __kkAtomicIntLoad()
    set(value) {
        __kkAtomicIntStore(value)
    }

/** Atomically swaps [expected] for [newValue] and returns the old value. */
public fun AtomicInt.compareAndSwap(expected: Int, newValue: Int): Int =
    __kkAtomicIntCompareAndExchange(expected, newValue)

/** Atomically adds [delta] and returns the value before the update. */
public fun AtomicInt.getAndAdd(delta: Int): Int =
    __kkAtomicIntFetchAndAdd(delta)

/** Atomically decrements and returns the value before the update. */
public fun AtomicInt.getAndDecrement(): Int =
    __kkAtomicIntFetchAndDecrement()

/** Atomically increments and returns the value before the update. */
public fun AtomicInt.getAndIncrement(): Int =
    __kkAtomicIntFetchAndIncrement()

/** Atomically increments the value by one. */
@Deprecated(
    "Use incrementAndGet() or getAndIncrement() instead.",
    ReplaceWith("this.incrementAndGet()"),
    DeprecationLevel.ERROR
)
public fun AtomicInt.increment(): Unit {
    __kkAtomicIntIncrementAndFetch()
}

/** Atomically decrements the value by one. */
@Deprecated(
    "Use decrementAndGet() or getAndDecrement() instead.",
    ReplaceWith("this.decrementAndGet()"),
    DeprecationLevel.ERROR
)
public fun AtomicInt.decrement(): Unit {
    __kkAtomicIntDecrementAndFetch()
}

/** Returns the string representation of the current atomic value. */
public fun AtomicInt.toString(): String = value.toString()

/**
 * A [Long] value that is always updated atomically.
 *
 * This is the legacy Kotlin/Native atomic API. Use
 * `kotlin.concurrent.atomics.AtomicLong` instead.
 */
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicLong instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicLong"),
    DeprecationLevel.ERROR
)
public class AtomicLong {
    @KsSymbolName("kk_atomic_long_create")
    public constructor(value: Long = 0L)
}

/**
 * A deprecated atomic wrapper around a native pointer.
 *
 * This declaration owns the top-level constructor only. The value property
 * and member operations remain separate migration surfaces.
 */
@Deprecated("Use kotlin.concurrent.atomics.AtomicNativePtr instead.", ReplaceWith("kotlin.concurrent.atomics.AtomicNativePtr"), DeprecationLevel.ERROR)
public class AtomicNativePtr {
    public constructor(value: NativePtr)
}

// KSP-1226: Keep the legacy native AtomicReference constructor source-backed.
// Its value and atomic member operations are owned by KSP-1227.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class AtomicReference<T>(value: T)

// KSP-1236: Keep the top-level class and constructor source-backed. The
// value property and member operations are owned by KSP-1237.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class FreezableAtomicReference<T> {
    @KsSymbolName("kk_freezable_atomic_ref_create")
    public constructor(value: T)
}
