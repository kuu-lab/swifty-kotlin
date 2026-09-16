/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Atomics.kt>.
 */

@file:OptIn(ExperimentalForeignApi::class)

package kotlin.native.concurrent

import kotlin.concurrent.Volatile
import kotlin.internal.KsSymbolName
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.NativePtr

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
        val oldValue = value
        value = newValue
        return oldValue
    }

    /** Atomically replaces the value when it matches [expected] by reference identity. */
    public fun compareAndSwap(expected: T, newValue: T): T {
        val oldValue = value
        if (oldValue === expected) {
            value = newValue
        }
        return oldValue
    }

    /** Returns the debug representation used by Kotlin/Native's legacy API. */
    public override fun toString(): String =
        "AtomicReference: ${idString(this)} -> ${debugString(value)}"
}

private fun idString(value: Any): String = value.hashCode().toString()

private fun debugString(value: Any?): String {
    if (value == null) return "null"
    if (value is AtomicReference<*>) return "AtomicReference: ${idString(value)}"
    return "${value}: ${idString(value)}"
}

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
