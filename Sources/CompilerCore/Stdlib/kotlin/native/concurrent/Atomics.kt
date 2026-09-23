/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Atomics.kt>.
 */

@file:OptIn(ExperimentalForeignApi::class)
@file:Suppress("DEPRECATION_ERROR")
package kotlin.native.concurrent

import kotlin.concurrent.Volatile
import kotlin.internal.KsSymbolName
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.NativePtr

@KsSymbolName("__kk_lazy_sync_lock")
private external fun __atomicSyncLock(lock: Any): Unit

@KsSymbolName("__kk_lazy_sync_unlock")
private external fun __atomicSyncUnlock(lock: Any): Unit

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

@KsSymbolName("__kk_atomic_long_load")
private external fun AtomicLong.__kkLoad(): Long

@KsSymbolName("__kk_atomic_long_store")
private external fun AtomicLong.__kkStore(value: Long): Long

@KsSymbolName("__kk_atomic_long_compareAndExchange")
private external fun AtomicLong.__kkCompareAndExchange(expected: Long, update: Long): Long

@KsSymbolName("__kk_atomic_long_fetchAndAdd")
private external fun AtomicLong.__kkFetchAndAdd(delta: Long): Long

@KsSymbolName("__kk_atomic_long_fetchAndIncrement")
private external fun AtomicLong.__kkFetchAndIncrement(): Long

@KsSymbolName("__kk_atomic_long_fetchAndDecrement")
private external fun AtomicLong.__kkFetchAndDecrement(): Long

@KsSymbolName("__kk_atomic_long_addAndFetch")
private external fun AtomicLong.__kkAddAndFetch(delta: Long): Long

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

    @Volatile
    public var value: Long
        get() = __kkLoad()
        set(value) {
            __kkStore(value)
        }

    @Deprecated(message = "Use addAndGet(delta: Long) instead.", level = DeprecationLevel.ERROR)
    public fun addAndGet(delta: Int): Long = __kkAddAndFetch(delta.toLong())

    public fun compareAndSwap(expected: Long, update: Long): Long =
        __kkCompareAndExchange(expected, update)

    @Deprecated("Use decrementAndGet() or getAndDecrement() instead.", ReplaceWith("this.decrementAndGet()"), DeprecationLevel.ERROR)
    public fun decrement(): Unit {
        __kkAddAndFetch(-1L)
    }

    public fun getAndAdd(delta: Long): Long = __kkFetchAndAdd(delta)

    public fun getAndDecrement(): Long = __kkFetchAndDecrement()

    public fun getAndIncrement(): Long = __kkFetchAndIncrement()

    @Deprecated("Use incrementAndGet() or getAndIncrement() instead.", ReplaceWith("this.incrementAndGet()"), DeprecationLevel.ERROR)
    public fun increment(): Unit {
        __kkAddAndFetch(1L)
    }

    public override fun toString(): String = value.toString()
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

// KSP-1226/KSP-1227: Keep the legacy native AtomicReference API source-backed.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class AtomicReference<T>(value: T) {
    @Volatile
    public var value: T = value

    /** Atomically replaces the value and returns the value observed before the replacement. */
    public fun getAndSet(newValue: T): T {
        __atomicSyncLock(this)
        try {
            val oldValue = value
            value = newValue
            return oldValue
        } finally {
            __atomicSyncUnlock(this)
        }
    }

    /** Atomically replaces the value when it matches [expected] by reference identity. */
    public fun compareAndSwap(expected: T, newValue: T): T {
        __atomicSyncLock(this)
        try {
            val oldValue = value
            if (oldValue === expected) {
                value = newValue
            }
            return oldValue
        } finally {
            __atomicSyncUnlock(this)
        }
    }

    /** Returns the debug representation used by Kotlin/Native's legacy API. */
    public override fun toString(): String =
        "AtomicReference: ${idString(this)} -> ${debugString(value)}"
}

private fun idString(value: Any): String = value.hashCode().toString()

private fun debugString(value: Any?): String {
    if (value == null) return "null"
    if (value is AtomicReference<*>) return "AtomicReference: ${idString(value)}"
    if (value is FreezableAtomicReference<*>) return "FreezableAtomicReference: ${idString(value)}"
    return "${value}: ${idString(value)}"
}

// KSP-1236/KSP-1237: Keep the legacy FreezableAtomicReference API
// source-backed.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class FreezableAtomicReference<T>(value: T) {
    @Volatile
    public var value: T = value

    /** Atomically replaces the value when it matches [expected] by reference identity. */
    public fun compareAndSet(expected: T, newValue: T): Boolean {
        __atomicSyncLock(this)
        try {
            val oldValue = value
            if (oldValue === expected) {
                value = newValue
                return true
            }
            return false
        } finally {
            __atomicSyncUnlock(this)
        }
    }

    /** Atomically replaces the value when it matches [expected] by reference identity. */
    public fun compareAndSwap(expected: T, newValue: T): T {
        __atomicSyncLock(this)
        try {
            val oldValue = value
            if (oldValue === expected) {
                value = newValue
            }
            return oldValue
        } finally {
            __atomicSyncUnlock(this)
        }
    }

    /** Returns the debug representation used by Kotlin/Native's legacy API. */
    public override fun toString(): String =
        "FreezableAtomicReference: ${idString(this)} -> ${debugString(value)}"
}
