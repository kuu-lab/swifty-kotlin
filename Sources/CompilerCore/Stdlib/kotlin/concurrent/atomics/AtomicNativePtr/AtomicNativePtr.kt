/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/concurrent/atomics/Atomics.native.kt>.
 */

@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

package kotlin.concurrent.atomics

import kotlinx.cinterop.NativePtr

// KSP-1121: `AtomicNativePtr` is a synthetic nominal class with no dedicated
// `__kk_atomic_native_ptr_*` runtime family; its `value` member is field-backed
// storage. The public receiver surface is kept as source-backed extensions that
// delegate to that storage, matching the sequential semantics of the
// kotlin.concurrent and kotlin.native.concurrent twins. `value` itself stays a
// member property; bodies spell `this.value` explicitly because a statement
// beginning with the `value` modifier keyword is not a valid top-level
// boundary here.

/** Atomically loads the value from this [AtomicNativePtr]. */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicNativePtr.load(): NativePtr =
    this.value

/** Atomically stores the [newValue] into this [AtomicNativePtr]. */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicNativePtr.store(newValue: NativePtr): Unit {
    this.value = newValue
}

/**
 * Atomically stores the [newValue] into this [AtomicNativePtr]
 * and returns the old value.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicNativePtr.exchange(newValue: NativePtr): NativePtr {
    val oldValue = this.value
    this.value = newValue
    return oldValue
}

/**
 * Atomically stores the [newValue] into this [AtomicNativePtr]
 * and returns the old value.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicNativePtr.getAndSet(newValue: NativePtr): NativePtr =
    exchange(newValue)

/**
 * Atomically stores the [newValue] into this [AtomicNativePtr]
 * if the current value equals the [expectedValue] and returns the old value.
 * Comparison of values is done by value.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicNativePtr.compareAndExchange(expectedValue: NativePtr, newValue: NativePtr): NativePtr {
    val oldValue = this.value
    if (oldValue == expectedValue) {
        this.value = newValue
    }
    return oldValue
}

/**
 * Atomically stores the [newValue] into this [AtomicNativePtr]
 * if the current value equals the [expectedValue] and returns `true` if the
 * operation was successful. Comparison of values is done by value.
 */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicNativePtr.compareAndSet(expectedValue: NativePtr, newValue: NativePtr): Boolean {
    val oldValue = this.value
    if (oldValue == expectedValue) {
        this.value = newValue
        return true
    }
    return false
}

/** Returns the string representation of the stored pointer value. */
@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicNativePtr.toString(): String =
    this.value.toString()
