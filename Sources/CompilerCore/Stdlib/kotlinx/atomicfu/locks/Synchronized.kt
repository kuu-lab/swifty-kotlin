/*
 * Derived from kotlinx-atomicfu 0.33.0 (fc175fc575419ca9eae0d3c14cefe9c5cd7ca351).
 * Copyright JetBrains s.r.o. Licensed under the Apache License, Version 2.0.
 */
package kotlinx.atomicfu.locks

import kotlin.internal.KsSymbolName
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract
import kotlin.time.Duration

@KsSymbolName("__kk_atomicfu_lock_new")
private external fun newAtomicfuLockKernel(ownerErrorKind: Int): Any
@KsSymbolName("__kk_atomicfu_lock_lock")
private external fun atomicfuLock(kernel: Any): Unit
@KsSymbolName("__kk_atomicfu_lock_try_lock")
private external fun atomicfuTryLock(kernel: Any, timeoutNanos: Long): Boolean
@KsSymbolName("__kk_atomicfu_lock_unlock")
private external fun atomicfuUnlock(kernel: Any): Unit

// A normal Kotlin nominal owns its real kernel through a GC-traced object field.
// No coroutine Mutex receiver or raw ordinary-wrapper address crosses this ABI.
public open class SynchronizedObject {
    private val kernel: Any = newAtomicfuLockKernel(1)
    public fun lock(): Unit = atomicfuLock(kernel)
    public fun tryLock(): Boolean = atomicfuTryLock(kernel, 0L)
    public fun unlock(): Unit = atomicfuUnlock(kernel)
}

public typealias ReentrantLock = SynchronizedObject
public fun reentrantLock(): ReentrantLock = ReentrantLock()
public inline fun <T> ReentrantLock.withLock(block: () -> T): T {
    lock()
    try {
        return block()
    } finally {
        unlock()
    }
}
public inline fun <T> synchronized(lock: SynchronizedObject, block: () -> T): T {
    lock.lock()
    try {
        return block()
    } finally {
        lock.unlock()
    }
}

// The owned kernel uses a FIFO waiter queue, a recursive owner count and a
// monotonic timeout. This is a blocking thread mutex, not a coroutine mutex.
public class SynchronousMutex {
    private val kernel: Any = newAtomicfuLockKernel(0)
    public fun tryLock(): Boolean = atomicfuTryLock(kernel, 0L)
    public fun tryLock(timeout: Duration): Boolean = atomicfuTryLock(kernel, timeout.atomicfuTimeoutNanos())
    public fun lock(): Unit = atomicfuLock(kernel)
    public fun unlock(): Unit = atomicfuUnlock(kernel)
}

@OptIn(ExperimentalContracts::class)
public inline fun <T> SynchronousMutex.withLock(block: () -> T): T {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    lock()
    return try {
        block()
    } finally {
        unlock()
    }
}

internal fun Duration.atomicfuTimeoutNanos(): Long = when {
    this == Duration.INFINITE -> -1L
    this <= Duration.ZERO -> 0L
    else -> inWholeNanoseconds
}
