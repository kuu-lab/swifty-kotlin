/*
 * Derived from kotlinx-atomicfu 0.33.0, commit fc175fc575419ca9eae0d3c14cefe9c5cd7ca351.
 * Copyright JetBrains s.r.o. Licensed under the Apache License, Version 2.0.
 */
@file:Suppress("DEPRECATION", "INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
package kotlinx.atomicfu

import kotlin.internal.InlineOnly

@Deprecated(
    message = "Atomic array types provided by the kotlinx-atomicfu are prone to various bugs and will be removed soon. " +
            "Use AtomicArray type and corresponding factory functions provided by the Kotlin standard library instead.",
    level = DeprecationLevel.WARNING,
    replaceWith = ReplaceWith("kotlin.concurrent.atomics.atomicArrayOfNulls<T>(size)")
)
@Suppress("DEPRECATION")
@OptionalJsName(ATOMIC_ARRAY_OF_NULLS)
public fun <T> atomicArrayOfNulls(size: Int): AtomicArray<T?> = AtomicArray(size)

public inline fun <T> AtomicRef<T>.loop(action: (T) -> Unit): Nothing {
    while (true) {
        action(value)
    }
}

public inline fun <T> AtomicRef<T>.update(function: (T) -> T) {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return
    }
}

public inline fun <T> AtomicRef<T>.getAndUpdate(function: (T) -> T): T {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return cur
    }
}

public inline fun <T> AtomicRef<T>.updateAndGet(function: (T) -> T): T {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return upd
    }
}

public inline fun AtomicBoolean.loop(action: (Boolean) -> Unit): Nothing {
    while (true) {
        action(value)
    }
}

public inline fun AtomicBoolean.update(function: (Boolean) -> Boolean) {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return
    }
}

public inline fun AtomicBoolean.getAndUpdate(function: (Boolean) -> Boolean): Boolean {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return cur
    }
}

public inline fun AtomicBoolean.updateAndGet(function: (Boolean) -> Boolean): Boolean {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return upd
    }
}

public inline fun AtomicInt.loop(action: (Int) -> Unit): Nothing {
    while (true) {
        action(value)
    }
}

public inline fun AtomicInt.update(function: (Int) -> Int) {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return
    }
}

public inline fun AtomicInt.getAndUpdate(function: (Int) -> Int): Int {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return cur
    }
}

public inline fun AtomicInt.updateAndGet(function: (Int) -> Int): Int {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return upd
    }
}

public inline fun AtomicLong.loop(action: (Long) -> Unit): Nothing {
    while (true) {
        action(value)
    }
}

public inline fun AtomicLong.update(function: (Long) -> Long) {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return
    }
}

public inline fun AtomicLong.getAndUpdate(function: (Long) -> Long): Long {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return cur
    }
}

public inline fun AtomicLong.updateAndGet(function: (Long) -> Long): Long {
    while (true) {
        val cur = value
        val upd = function(cur)
        if (compareAndSet(cur, upd)) return upd
    }
}

// ==================================== AtomicIntArray ====================================

/**
 * Creates a new array of AtomicInt values of the specified size, where each element is initialised with 0
 */
@Deprecated(
    message = "Atomic array types provided by the kotlinx-atomicfu are prone to various bugs and will be removed soon. " +
            "Use AtomicIntArray type provided by the Kotlin standard library instead.",
    level = DeprecationLevel.WARNING,
    replaceWith = ReplaceWith("kotlin.concurrent.atomics.AtomicIntArray")
)
@Suppress("DEPRECATION")
@OptionalJsName(ATOMIC_INT_ARRAY)
public class AtomicIntArray
@Deprecated(
    message = "Atomic array types provided by the kotlinx-atomicfu are prone to various bugs and will be removed soon. " +
            "Use AtomicIntArray type provided by the Kotlin standard library instead.",
    level = DeprecationLevel.WARNING,
    replaceWith = ReplaceWith("kotlin.concurrent.atomics.AtomicIntArray(size)")
)
public constructor(size: Int) {
    private val array = Array(size) { atomic(0) }

    @OptionalJsName(ARRAY_SIZE)
    public val size: Int
        get() = array.size

    @OptionalJsName(ARRAY_ELEMENT_GET)
    public operator fun get(index: Int): AtomicInt = array[index]
}

// ==================================== AtomicLongArray ====================================

/**
 * Creates a new array of AtomicLong values of the specified size, where each element is initialised with 0L
 */
@Deprecated(
    message = "Atomic array types provided by the kotlinx-atomicfu are prone to various bugs and will be removed soon. " +
            "Use AtomicLongArray type provided by the Kotlin standard library instead.",
    level = DeprecationLevel.WARNING,
    replaceWith = ReplaceWith("kotlin.concurrent.atomics.AtomicLongArray")
)
@Suppress("DEPRECATION")
@OptionalJsName(ATOMIC_LONG_ARRAY)
public class AtomicLongArray
@Deprecated(
    message = "Atomic array types provided by the kotlinx-atomicfu are prone to various bugs and will be removed soon. " +
            "Use AtomicLongArray type provided by the Kotlin standard library instead.",
    level = DeprecationLevel.WARNING,
    replaceWith = ReplaceWith("kotlin.concurrent.atomics.AtomicLongArray(size)")
)
public constructor(size: Int) {
    private val array = Array(size) { atomic(0L) }

    @OptionalJsName(ARRAY_SIZE)
    public val size: Int
        get() = array.size

    @OptionalJsName(ARRAY_ELEMENT_GET)
    public operator fun get(index: Int): AtomicLong = array[index]
}

// ==================================== AtomicBooleanArray ====================================

/**
 * Creates a new array of AtomicBoolean values of the specified size, where each element is initialised with false
 */
@Suppress("DEPRECATION")
@OptionalJsName(ATOMIC_BOOLEAN_ARRAY)
@Deprecated(
    message = "Atomic array types provided by the kotlinx-atomicfu are prone to various bugs and will be removed soon. " +
            "There is no direct replacement for this type in the standard library. " +
            "Consider encoding boolean values as Int constants and using kotlin.concurrent.atomics.AtomicIntArray instead.",
    level = DeprecationLevel.WARNING
)
public class AtomicBooleanArray(size: Int) {
    private val array = Array(size) { atomic(false) }

    @OptionalJsName(ARRAY_SIZE)
    public val size: Int
        get() = array.size

    @OptionalJsName(ARRAY_ELEMENT_GET)
    public operator fun get(index: Int): AtomicBoolean = array[index]
}


// ==================================== AtomicArray ====================================
@Deprecated(
    message = "Atomic array types provided by the kotlinx-atomicfu are prone to various bugs and will be removed soon. " +
            "Use AtomicArray type provided by the Kotlin standard library instead.",
    level = DeprecationLevel.WARNING,
    replaceWith = ReplaceWith("kotlin.concurrent.atomics.AtomicArray<T>")
)
@Suppress("DEPRECATION")
@OptionalJsName(ATOMIC_REF_ARRAY)
public class AtomicArray<T> internal constructor(size: Int) {
    private val array = Array(size) { atomic<T?>(null) }

    @OptionalJsName(ARRAY_SIZE)
    public val size: Int
        get() = array.size

    @OptionalJsName(ARRAY_ELEMENT_GET)
    public operator fun get(index: Int): AtomicRef<T?> = array[index]
}
