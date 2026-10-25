package java.util.concurrent.atomic

import kotlin.internal.KsSymbolName

// KUU-3059: java.util.concurrent.atomic.AtomicLongArray shares the
// `__kk_atomic_long_array_*` runtime boxes with kotlin.concurrent's
// AtomicLongArray family. See AtomicIntegerArray.kt for the layout notes.

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

public fun AtomicLongArray.exchangeAt(index: Int, newValue: Long): Long {
    checkIndex(index)
    return __kk_exchange(index, newValue)
}

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

public fun AtomicLongArray.addAndFetchAt(index: Int, delta: Long): Long {
    checkIndex(index)
    return __kk_addAndFetch(index, delta)
}

public fun AtomicLongArray.fetchAndIncrementAt(index: Int): Long = fetchAndAddAt(index, 1L)

public fun AtomicLongArray.incrementAndFetchAt(index: Int): Long = addAndFetchAt(index, 1L)

public fun AtomicLongArray.fetchAndDecrementAt(index: Int): Long = fetchAndAddAt(index, -1L)

public fun AtomicLongArray.decrementAndFetchAt(index: Int): Long = addAndFetchAt(index, -1L)

public class AtomicLongArray private constructor() {
    public fun length(): Int = size

    public operator fun get(index: Int): Long = loadAt(index)

    public operator fun set(index: Int, newValue: Long): Unit = storeAt(index, newValue)

    public fun getAndSet(index: Int, newValue: Long): Long = exchangeAt(index, newValue)

    public fun lazySet(index: Int, newValue: Long): Unit = storeAt(index, newValue)

    public fun compareAndSet(index: Int, expectedValue: Long, update: Long): Boolean =
        compareAndSetAt(index, expectedValue, update)

    public fun weakCompareAndSet(index: Int, expectedValue: Long, update: Long): Boolean =
        compareAndSet(index, expectedValue, update)

    public fun getAndAdd(index: Int, delta: Long): Long = fetchAndAddAt(index, delta)

    public fun addAndGet(index: Int, delta: Long): Long = addAndFetchAt(index, delta)

    public fun incrementAndGet(index: Int): Long = incrementAndFetchAt(index)

    public fun getAndIncrement(index: Int): Long = fetchAndIncrementAt(index)

    public fun decrementAndGet(index: Int): Long = decrementAndFetchAt(index)

    public fun getAndDecrement(index: Int): Long = fetchAndDecrementAt(index)

    public fun getAndUpdate(index: Int, transform: (Long) -> Long): Long {
        while (true) {
            val old = loadAt(index)
            val newValue = transform(old)
            if (compareAndSetAt(index, old, newValue)) return old
        }
    }

    public fun updateAndGet(index: Int, transform: (Long) -> Long): Long {
        while (true) {
            val old = loadAt(index)
            val newValue = transform(old)
            if (compareAndSetAt(index, old, newValue)) return newValue
        }
    }

    public fun getAndAccumulate(index: Int, x: Long, accumulator: (Long, Long) -> Long): Long {
        while (true) {
            val old = loadAt(index)
            val newValue = accumulator(old, x)
            if (compareAndSetAt(index, old, newValue)) return old
        }
    }

    public fun accumulateAndGet(index: Int, x: Long, accumulator: (Long, Long) -> Long): Long {
        while (true) {
            val old = loadAt(index)
            val newValue = accumulator(old, x)
            if (compareAndSetAt(index, old, newValue)) return newValue
        }
    }

    public override fun toString(): String {
        val builder = StringBuilder()
        builder.append("[")
        var index = 0
        while (index < size) {
            if (index > 0) builder.append(", ")
            builder.append(loadAt(index))
            index++
        }
        builder.append("]")
        return builder.toString()
    }
}
