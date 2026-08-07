package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

// MIGRATION-ATOMIC-ARRAY-001 (KSP-672)
// The public `*At` boundary layer and index bounds checks for AtomicIntArray /
// AtomicLongArray are implemented here in Kotlin. Only the raw synchronized core
// stays in the runtime, reached through the `__kk_atomic_*_array_*` bridges.
// Bounds checks always use `this.size` (an implicit `size` receiver inside a
// bundled extension does not bind to the array length).
// Migration source: Sources/Runtime/RuntimeAtomic.swift
//   __kk_atomic_int_array_* / __kk_atomic_long_array_*
// CAS/arithmetic cores (compareAndExchange, fetchAndAdd, addAndFetch) and the
// lambda-driven fetchAndUpdateAt remain runtime bridges.

// ---- AtomicIntArray ----

@KsSymbolName("__kk_atomic_int_array_load")
private external fun AtomicIntArray.__kk_load(index: Int): Int

@KsSymbolName("__kk_atomic_int_array_store")
private external fun AtomicIntArray.__kk_store(index: Int, value: Int): Int

@KsSymbolName("__kk_atomic_int_array_exchange")
private external fun AtomicIntArray.__kk_exchange(index: Int, newValue: Int): Int

@KsSymbolName("__kk_atomic_int_array_compareAndExchange")
private external fun AtomicIntArray.__kk_compareAndExchange(index: Int, expectedValue: Int, update: Int): Int

@KsSymbolName("__kk_atomic_int_array_fetchAndAdd")
private external fun AtomicIntArray.__kk_fetchAndAdd(index: Int, delta: Int): Int

@KsSymbolName("__kk_atomic_int_array_addAndFetch")
private external fun AtomicIntArray.__kk_addAndFetch(index: Int, delta: Int): Int

private fun AtomicIntArray.checkIndex(index: Int) {
    val size = this.size
    if (index < 0 || index >= size) {
        throw IndexOutOfBoundsException("Index $index out of bounds for length $size")
    }
}

public fun AtomicIntArray.loadAt(index: Int): Int {
    checkIndex(index)
    return __kk_load(index)
}

public fun AtomicIntArray.storeAt(index: Int, value: Int): Unit {
    checkIndex(index)
    __kk_store(index, value)
}

public operator fun AtomicIntArray.get(index: Int): Int = loadAt(index)

public operator fun AtomicIntArray.set(index: Int, value: Int): Unit = storeAt(index, value)

public fun AtomicIntArray.exchangeAt(index: Int, newValue: Int): Int {
    checkIndex(index)
    return __kk_exchange(index, newValue)
}

public fun AtomicIntArray.getAndSet(index: Int, newValue: Int): Int = exchangeAt(index, newValue)

public fun AtomicIntArray.compareAndSetAt(index: Int, expectedValue: Int, update: Int): Boolean {
    checkIndex(index)
    return __kk_compareAndExchange(index, expectedValue, update) == expectedValue
}

public fun AtomicIntArray.compareAndExchangeAt(index: Int, expectedValue: Int, update: Int): Int {
    checkIndex(index)
    return __kk_compareAndExchange(index, expectedValue, update)
}

public fun AtomicIntArray.fetchAndAddAt(index: Int, delta: Int): Int {
    checkIndex(index)
    return __kk_fetchAndAdd(index, delta)
}

public fun AtomicIntArray.getAndAdd(index: Int, delta: Int): Int = fetchAndAddAt(index, delta)

public fun AtomicIntArray.addAndFetchAt(index: Int, delta: Int): Int {
    checkIndex(index)
    return __kk_addAndFetch(index, delta)
}

public fun AtomicIntArray.addAndGet(index: Int, delta: Int): Int = addAndFetchAt(index, delta)

public fun AtomicIntArray.fetchAndIncrementAt(index: Int): Int = fetchAndAddAt(index, 1)

public fun AtomicIntArray.getAndIncrement(index: Int): Int = fetchAndAddAt(index, 1)

public fun AtomicIntArray.incrementAndFetchAt(index: Int): Int = addAndFetchAt(index, 1)

public fun AtomicIntArray.incrementAndGet(index: Int): Int = addAndFetchAt(index, 1)

public fun AtomicIntArray.fetchAndDecrementAt(index: Int): Int = fetchAndAddAt(index, -1)

public fun AtomicIntArray.getAndDecrement(index: Int): Int = fetchAndAddAt(index, -1)

public fun AtomicIntArray.decrementAndFetchAt(index: Int): Int = addAndFetchAt(index, -1)

public fun AtomicIntArray.decrementAndGet(index: Int): Int = addAndFetchAt(index, -1)

// ---- AtomicLongArray ----

@KsSymbolName("__kk_atomic_long_array_load")
private external fun AtomicLongArray.__kk_load(index: Int): Long

@KsSymbolName("__kk_atomic_long_array_store")
private external fun AtomicLongArray.__kk_store(index: Int, value: Long): Long

@KsSymbolName("__kk_atomic_long_array_exchange")
private external fun AtomicLongArray.__kk_exchange(index: Int, newValue: Long): Long

@KsSymbolName("__kk_atomic_long_array_compareAndExchange")
private external fun AtomicLongArray.__kk_compareAndExchange(index: Int, expectedValue: Long, update: Long): Long

@KsSymbolName("__kk_atomic_long_array_fetchAndAdd")
private external fun AtomicLongArray.__kk_fetchAndAdd(index: Int, delta: Long): Long

@KsSymbolName("__kk_atomic_long_array_addAndFetch")
private external fun AtomicLongArray.__kk_addAndFetch(index: Int, delta: Long): Long

private fun AtomicLongArray.checkIndex(index: Int) {
    val size = this.size
    if (index < 0 || index >= size) {
        throw IndexOutOfBoundsException("Index $index out of bounds for length $size")
    }
}

public fun AtomicLongArray.loadAt(index: Int): Long {
    checkIndex(index)
    return __kk_load(index)
}

public fun AtomicLongArray.storeAt(index: Int, value: Long): Unit {
    checkIndex(index)
    __kk_store(index, value)
}

public operator fun AtomicLongArray.get(index: Int): Long = loadAt(index)

public operator fun AtomicLongArray.set(index: Int, value: Long): Unit = storeAt(index, value)

public fun AtomicLongArray.exchangeAt(index: Int, newValue: Long): Long {
    checkIndex(index)
    return __kk_exchange(index, newValue)
}

public fun AtomicLongArray.getAndSet(index: Int, newValue: Long): Long = exchangeAt(index, newValue)

public fun AtomicLongArray.compareAndSetAt(index: Int, expectedValue: Long, update: Long): Boolean {
    checkIndex(index)
    return __kk_compareAndExchange(index, expectedValue, update) == expectedValue
}

public fun AtomicLongArray.compareAndExchangeAt(index: Int, expectedValue: Long, update: Long): Long {
    checkIndex(index)
    return __kk_compareAndExchange(index, expectedValue, update)
}

public fun AtomicLongArray.fetchAndAddAt(index: Int, delta: Long): Long {
    checkIndex(index)
    return __kk_fetchAndAdd(index, delta)
}

public fun AtomicLongArray.getAndAdd(index: Int, delta: Long): Long = fetchAndAddAt(index, delta)

public fun AtomicLongArray.addAndFetchAt(index: Int, delta: Long): Long {
    checkIndex(index)
    return __kk_addAndFetch(index, delta)
}

public fun AtomicLongArray.addAndGet(index: Int, delta: Long): Long = addAndFetchAt(index, delta)

public fun AtomicLongArray.fetchAndIncrementAt(index: Int): Long = fetchAndAddAt(index, 1L)

public fun AtomicLongArray.getAndIncrement(index: Int): Long = fetchAndAddAt(index, 1L)

public fun AtomicLongArray.incrementAndFetchAt(index: Int): Long = addAndFetchAt(index, 1L)

public fun AtomicLongArray.incrementAndGet(index: Int): Long = addAndFetchAt(index, 1L)

public fun AtomicLongArray.fetchAndDecrementAt(index: Int): Long = fetchAndAddAt(index, -1L)

public fun AtomicLongArray.getAndDecrement(index: Int): Long = fetchAndAddAt(index, -1L)

public fun AtomicLongArray.decrementAndFetchAt(index: Int): Long = addAndFetchAt(index, -1L)

public fun AtomicLongArray.decrementAndGet(index: Int): Long = addAndFetchAt(index, -1L)
