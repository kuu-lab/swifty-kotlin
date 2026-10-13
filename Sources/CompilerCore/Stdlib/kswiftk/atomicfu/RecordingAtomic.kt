/* KSwiftK explicit recording mode; ordinary Native scalar APIs remain unchanged.
 * Modification message conventions derive from atomicfu 0.33.0 JVM AtomicFU.kt.
 * Copyright JetBrains s.r.o. Licensed under the Apache License, Version 2.0. */
@file:Suppress("DEPRECATION")
package kswiftk.atomicfu

import kotlin.reflect.KProperty
import kotlinx.atomicfu.TraceBase
import kotlinx.atomicfu.AtomicInt
import kotlinx.atomicfu.AtomicLong
import kotlinx.atomicfu.AtomicBoolean
import kotlinx.atomicfu.AtomicRef
import kotlinx.atomicfu.atomic

/** Explicit factory; delegate always uses ordinary Native None tracing. */
public fun recordingAtomic(initial: Int, trace: TraceBase = RecordingTrace()): RecordingAtomicInt =
    RecordingAtomicInt(atomic(initial), trace)

public class RecordingAtomicInt internal constructor(
    private val delegate: AtomicInt,
    public val trace: TraceBase
) {
    // Log after the genuine mutation. A callback failure propagates without rollback.
    // None bypasses interpolation, so no payload.toString side effect is introduced.
    public var value: Int
        get() = delegate.value
        set(value) {
            delegate.value = value
            if (trace !== TraceBase.None) trace.append("set($value)")
        }
    public operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = value
    public operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) { this.value = value }
    public fun lazySet(value: Int) {
        delegate.lazySet(value)
        if (trace !== TraceBase.None) trace.append("lazySet($value)")
    }
    public fun compareAndSet(expect: Int, update: Int): Boolean {
        val result = delegate.compareAndSet(expect, update)
        if (result && trace !== TraceBase.None) trace.append("CAS($expect, $update)")
        return result
    }
    public fun getAndSet(value: Int): Int {
        val previous = delegate.getAndSet(value)
        if (trace !== TraceBase.None) trace.append("getAndSet($value):$previous")
        return previous
    }
    public fun getAndIncrement(): Int {
        val result = delegate.getAndIncrement()
        if (trace !== TraceBase.None) trace.append("getAndInc():$result")
        return result
    }
    public fun getAndDecrement(): Int {
        val result = delegate.getAndDecrement()
        if (trace !== TraceBase.None) trace.append("getAndDec():$result")
        return result
    }
    public fun getAndAdd(delta: Int): Int {
        val result = delegate.getAndAdd(delta)
        if (trace !== TraceBase.None) trace.append("getAndAdd($delta):$result")
        return result
    }
    public fun addAndGet(delta: Int): Int {
        val result = delegate.addAndGet(delta)
        if (trace !== TraceBase.None) trace.append("addAndGet($delta):$result")
        return result
    }
    public fun incrementAndGet(): Int {
        val result = delegate.incrementAndGet()
        if (trace !== TraceBase.None) trace.append("incAndGet():$result")
        return result
    }
    public fun decrementAndGet(): Int {
        val result = delegate.decrementAndGet()
        if (trace !== TraceBase.None) trace.append("decAndGet():$result")
        return result
    }
    public operator fun plusAssign(delta: Int) { getAndAdd(delta) }
    public operator fun minusAssign(delta: Int) { getAndAdd(-delta) }
    override fun toString(): String = value.toString()
}

/** Explicit factory; delegate always uses ordinary Native None tracing. */
public fun recordingAtomic(initial: Long, trace: TraceBase = RecordingTrace()): RecordingAtomicLong =
    RecordingAtomicLong(atomic(initial), trace)

public class RecordingAtomicLong internal constructor(
    private val delegate: AtomicLong,
    public val trace: TraceBase
) {
    // Log after the genuine mutation. A callback failure propagates without rollback.
    // None bypasses interpolation, so no payload.toString side effect is introduced.
    public var value: Long
        get() = delegate.value
        set(value) {
            delegate.value = value
            if (trace !== TraceBase.None) trace.append("set($value)")
        }
    public operator fun getValue(thisRef: Any?, property: KProperty<*>): Long = value
    public operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Long) { this.value = value }
    public fun lazySet(value: Long) {
        delegate.lazySet(value)
        if (trace !== TraceBase.None) trace.append("lazySet($value)")
    }
    public fun compareAndSet(expect: Long, update: Long): Boolean {
        val result = delegate.compareAndSet(expect, update)
        if (result && trace !== TraceBase.None) trace.append("CAS($expect, $update)")
        return result
    }
    public fun getAndSet(value: Long): Long {
        val previous = delegate.getAndSet(value)
        if (trace !== TraceBase.None) trace.append("getAndSet($value):$previous")
        return previous
    }
    public fun getAndIncrement(): Long {
        val result = delegate.getAndIncrement()
        if (trace !== TraceBase.None) trace.append("getAndInc():$result")
        return result
    }
    public fun getAndDecrement(): Long {
        val result = delegate.getAndDecrement()
        if (trace !== TraceBase.None) trace.append("getAndDec():$result")
        return result
    }
    public fun getAndAdd(delta: Long): Long {
        val result = delegate.getAndAdd(delta)
        if (trace !== TraceBase.None) trace.append("getAndAdd($delta):$result")
        return result
    }
    public fun addAndGet(delta: Long): Long {
        val result = delegate.addAndGet(delta)
        if (trace !== TraceBase.None) trace.append("addAndGet($delta):$result")
        return result
    }
    public fun incrementAndGet(): Long {
        val result = delegate.incrementAndGet()
        if (trace !== TraceBase.None) trace.append("incAndGet():$result")
        return result
    }
    public fun decrementAndGet(): Long {
        val result = delegate.decrementAndGet()
        if (trace !== TraceBase.None) trace.append("decAndGet():$result")
        return result
    }
    public operator fun plusAssign(delta: Long) { getAndAdd(delta) }
    public operator fun minusAssign(delta: Long) { getAndAdd(-delta) }
    override fun toString(): String = value.toString()
}

/** Explicit factory; delegate always uses ordinary Native None tracing. */
public fun recordingAtomic(initial: Boolean, trace: TraceBase = RecordingTrace()): RecordingAtomicBoolean =
    RecordingAtomicBoolean(atomic(initial), trace)

public class RecordingAtomicBoolean internal constructor(
    private val delegate: AtomicBoolean,
    public val trace: TraceBase
) {
    // Log after the genuine mutation. A callback failure propagates without rollback.
    // None bypasses interpolation, so no payload.toString side effect is introduced.
    public var value: Boolean
        get() = delegate.value
        set(value) {
            delegate.value = value
            if (trace !== TraceBase.None) trace.append("set($value)")
        }
    public operator fun getValue(thisRef: Any?, property: KProperty<*>): Boolean = value
    public operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Boolean) { this.value = value }
    public fun lazySet(value: Boolean) {
        delegate.lazySet(value)
        if (trace !== TraceBase.None) trace.append("lazySet($value)")
    }
    public fun compareAndSet(expect: Boolean, update: Boolean): Boolean {
        val result = delegate.compareAndSet(expect, update)
        if (result && trace !== TraceBase.None) trace.append("CAS($expect, $update)")
        return result
    }
    public fun getAndSet(value: Boolean): Boolean {
        val previous = delegate.getAndSet(value)
        if (trace !== TraceBase.None) trace.append("getAndSet($value):$previous")
        return previous
    }
    override fun toString(): String = value.toString()
}

/** Explicit factory; delegate always uses ordinary Native None tracing. */
public fun <T> recordingAtomic(initial: T, trace: TraceBase = RecordingTrace()): RecordingAtomicRef<T> =
    RecordingAtomicRef(atomic<T>(initial), trace)

public class RecordingAtomicRef<T> internal constructor(
    private val delegate: AtomicRef<T>,
    public val trace: TraceBase
) {
    // Log after the genuine mutation. A callback failure propagates without rollback.
    // None bypasses interpolation, so no payload.toString side effect is introduced.
    public var value: T
        get() = delegate.value
        set(value) {
            delegate.value = value
            if (trace !== TraceBase.None) trace.append("set($value)")
        }
    public operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value
    public operator fun setValue(thisRef: Any?, property: KProperty<*>, value: T) { this.value = value }
    public fun lazySet(value: T) {
        delegate.lazySet(value)
        if (trace !== TraceBase.None) trace.append("lazySet($value)")
    }
    public fun compareAndSet(expect: T, update: T): Boolean {
        val result = delegate.compareAndSet(expect, update)
        if (result && trace !== TraceBase.None) trace.append("CAS($expect, $update)")
        return result
    }
    public fun getAndSet(value: T): T {
        val previous = delegate.getAndSet(value)
        if (trace !== TraceBase.None) trace.append("getAndSet($value):$previous")
        return previous
    }
    override fun toString(): String = value.toString()
}
