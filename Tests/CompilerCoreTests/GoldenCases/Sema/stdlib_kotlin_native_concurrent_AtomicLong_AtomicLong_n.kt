@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.AtomicLong

fun atomicLongValue(atomic: AtomicLong): Long = atomic.value

fun atomicLongAddAndGet(atomic: AtomicLong, delta: Int): Long = atomic.addAndGet(delta)

fun atomicLongCompareAndSwap(atomic: AtomicLong, expected: Long, update: Long): Long =
    atomic.compareAndSwap(expected, update)

fun atomicLongDecrement(atomic: AtomicLong): Unit = atomic.decrement()

fun atomicLongGetAndAdd(atomic: AtomicLong, delta: Long): Long = atomic.getAndAdd(delta)

fun atomicLongGetAndDecrement(atomic: AtomicLong): Long = atomic.getAndDecrement()

fun atomicLongGetAndIncrement(atomic: AtomicLong): Long = atomic.getAndIncrement()

fun atomicLongIncrement(atomic: AtomicLong): Unit = atomic.increment()

fun atomicLongToString(atomic: AtomicLong): String = atomic.toString()
