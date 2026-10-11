/*
 * Copyright 2017-2018 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:Suppress(
    "NOTHING_TO_INLINE",
    "RedundantVisibilityModifier",
    "CanBePrimaryConstructorProperty",
    "INVISIBLE_REFERENCE",
    "INVISIBLE_MEMBER"
)

package kotlinx.atomicfu

import kotlin.concurrent.AtomicInt as KAtomicInt
import kotlin.concurrent.AtomicLong as KAtomicLong
import kotlin.concurrent.AtomicReference as KAtomicRef
import kotlin.concurrent.compareAndSet as standardCompareAndSet
import kotlin.concurrent.addAndGet as standardAddAndGet
import kotlin.reflect.KProperty
import kotlinx.atomicfu.TraceBase.None
import kotlin.internal.InlineOnly

public fun <T> atomic(initial: T, trace: TraceBase = None): AtomicRef<T> = AtomicRef<T>(KAtomicRef(initial))
public fun <T> atomic(initial: T): AtomicRef<T> = atomic(initial, None)
public fun atomic(initial: Int, trace: TraceBase = None): AtomicInt = AtomicInt(KAtomicInt(initial))
public fun atomic(initial: Int): AtomicInt = atomic(initial, None)
public fun atomic(initial: Long, trace: TraceBase = None): AtomicLong = AtomicLong(KAtomicLong(initial))
public fun atomic(initial: Long): AtomicLong = atomic(initial, None)
public fun atomic(initial: Boolean, trace: TraceBase = None): AtomicBoolean = AtomicBoolean(KAtomicInt(if (initial) 1 else 0))
public fun atomic(initial: Boolean): AtomicBoolean = atomic(initial, None)

// ==================================== AtomicRef ====================================

public class AtomicRef<T> internal constructor(@PublishedApi internal val a: KAtomicRef<T>) {
    public inline var value: T
        get() = a.value
        set(value) {
            a.value = value
        }

    @InlineOnly
    public inline operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value

    @InlineOnly
    public inline operator fun setValue(thisRef: Any?, property: KProperty<*>, value: T) { this.value = value }

    public inline fun lazySet(value: T) {
        a.value = value
    }

    public inline fun compareAndSet(expect: T, update: T): Boolean {
        return a.standardCompareAndSet(expect, update)
    }

    // The standard member owns class-T nullable/ref marshalling and the real
    // atomic exchange kernel. Never pass this ordinary wrapper as a raw box.
    public fun getAndSet(value: T): T = a.getAndSet(value)

    override fun toString(): String = value.toString()
}

// ==================================== AtomicBoolean ====================================

public class AtomicBoolean internal constructor(@PublishedApi internal val a: KAtomicInt) {
    public inline var value: Boolean
        get() = a.value != 0
        set(value) { a.value = if (value) 1 else 0 }

    @InlineOnly
    public inline operator fun getValue(thisRef: Any?, property: KProperty<*>): Boolean = value

    @InlineOnly
    public inline operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Boolean) { this.value = value }

    public inline fun lazySet(value: Boolean) { this.value = value }

    public fun compareAndSet(expect: Boolean, update: Boolean): Boolean {
        val iExpect = if (expect) 1 else 0
        val iUpdate = if (update) 1 else 0
        return a.standardCompareAndSet(iExpect, iUpdate)
    }

    public fun getAndSet(value: Boolean): Boolean {
        val iValue = if (value) 1 else 0
        while (true) {
            val cur = a.value
            if (cur == iValue) return value
            if (a.standardCompareAndSet(cur, iValue)) return cur != 0
        }
    }

    override fun toString(): String = value.toString()
}

// ==================================== AtomicInt ====================================

public class AtomicInt internal constructor(@PublishedApi internal val a: KAtomicInt) {
    public inline var value: Int
        get() = a.value
        set(value) { a.value = value }

    @InlineOnly
    public inline operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = value

    @InlineOnly
    public inline operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) { this.value = value }

    public inline fun lazySet(value: Int) { a.value = value }

    public inline fun compareAndSet(expect: Int, update: Int): Boolean =
        a.standardCompareAndSet(expect, update)

    public fun getAndSet(value: Int): Int {
        while (true) {
            val cur = a.value
            if (cur == value) return cur
            if (a.standardCompareAndSet(cur, value)) return cur
        }
    }

    public inline fun getAndIncrement(): Int = a.standardAddAndGet(1) - 1
    public inline fun getAndDecrement(): Int = a.standardAddAndGet(-1) + 1
    public inline fun getAndAdd(delta: Int): Int = a.standardAddAndGet(delta) - delta
    public inline fun addAndGet(delta: Int): Int = a.standardAddAndGet(delta)
    public inline fun incrementAndGet(): Int = a.standardAddAndGet(1)
    public inline fun decrementAndGet(): Int = a.standardAddAndGet(-1)

    public inline operator fun plusAssign(delta: Int) { getAndAdd(delta) }
    public inline operator fun minusAssign(delta: Int) { getAndAdd(-delta) }

    override fun toString(): String = value.toString()
}

// ==================================== AtomicLong ====================================

public class AtomicLong internal constructor(@PublishedApi internal val a: KAtomicLong) {
    public inline var value: Long
        get() = a.value
        set(value) { a.value = value }

    @InlineOnly
    public inline operator fun getValue(thisRef: Any?, property: KProperty<*>): Long = value

    @InlineOnly
    public inline operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Long) { this.value = value }

    public inline fun lazySet(value: Long) { a.value = value }

    public inline fun compareAndSet(expect: Long, update: Long): Boolean =
        a.standardCompareAndSet(expect, update)

    public fun getAndSet(value: Long): Long {
        while (true) {
            val cur = a.value
            if (cur == value) return cur
            if (a.standardCompareAndSet(cur, value)) return cur
        }
    }

    public inline fun getAndIncrement(): Long = a.standardAddAndGet(1L) - 1
    public inline fun getAndDecrement(): Long = a.standardAddAndGet(-1L) + 1
    public inline fun getAndAdd(delta: Long): Long = a.standardAddAndGet(delta) - delta
    public inline fun addAndGet(delta: Long): Long = a.standardAddAndGet(delta)
    public inline fun incrementAndGet(): Long = a.standardAddAndGet(1L)
    public inline fun decrementAndGet(): Long = a.standardAddAndGet(-1L)

    public inline operator fun plusAssign(delta: Long) { getAndAdd(delta) }
    public inline operator fun minusAssign(delta: Long) { getAndAdd(-delta) }

    override fun toString(): String = value.toString()
}
