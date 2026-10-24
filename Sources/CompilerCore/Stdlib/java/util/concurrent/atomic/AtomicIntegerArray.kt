package java.util.concurrent.atomic

import kotlin.internal.KsSymbolName

// KUU-3059: java.util.concurrent.atomic.AtomicIntegerArray shares the
// `__kk_atomic_int_array_*` runtime boxes with kotlin.concurrent's
// AtomicIntArray family (see Stdlib/kotlin/concurrent/AtomicArrayCompatMigration.kt).
// The synthetic registration supplies the class shell, the
// `AtomicIntegerArray(size: Int)` constructor and the `size` property; the
// `*At` boundary layer and the JVM-named members live here in Kotlin so the
// bounds checks and raw bridges stay in one implementation.

@KsSymbolName("__kk_atomic_int_array_load")
private external fun AtomicIntegerArray.__kk_load(index: Int): Int

@KsSymbolName("__kk_atomic_int_array_store")
private external fun AtomicIntegerArray.__kk_store(index: Int, value: Int): Int

@KsSymbolName("__kk_atomic_int_array_exchange")
private external fun AtomicIntegerArray.__kk_exchange(index: Int, newValue: Int): Int

@KsSymbolName("__kk_atomic_int_array_compareAndExchange")
private external fun AtomicIntegerArray.__kk_compareAndExchange(index: Int, expectedValue: Int, update: Int): Int

@KsSymbolName("__kk_atomic_int_array_fetchAndAdd")
private external fun AtomicIntegerArray.__kk_fetchAndAdd(index: Int, delta: Int): Int

@KsSymbolName("__kk_atomic_int_array_addAndFetch")
private external fun AtomicIntegerArray.__kk_addAndFetch(index: Int, delta: Int): Int

private fun AtomicIntegerArray.checkIndex(index: Int) {
    val size = this.size
    if (index < 0 || index >= size) {
        throw IndexOutOfBoundsException("Index $index out of bounds for length $size")
    }
}

public fun AtomicIntegerArray.loadAt(index: Int): Int {
    checkIndex(index)
    return __kk_load(index)
}

public fun AtomicIntegerArray.storeAt(index: Int, value: Int): Unit {
    checkIndex(index)
    __kk_store(index, value)
}

public fun AtomicIntegerArray.exchangeAt(index: Int, newValue: Int): Int {
    checkIndex(index)
    return __kk_exchange(index, newValue)
}

public fun AtomicIntegerArray.compareAndSetAt(index: Int, expectedValue: Int, update: Int): Boolean {
    checkIndex(index)
    return __kk_compareAndExchange(index, expectedValue, update) == expectedValue
}

public fun AtomicIntegerArray.compareAndExchangeAt(index: Int, expectedValue: Int, update: Int): Int {
    checkIndex(index)
    return __kk_compareAndExchange(index, expectedValue, update)
}

public fun AtomicIntegerArray.fetchAndAddAt(index: Int, delta: Int): Int {
    checkIndex(index)
    return __kk_fetchAndAdd(index, delta)
}

public fun AtomicIntegerArray.addAndFetchAt(index: Int, delta: Int): Int {
    checkIndex(index)
    return __kk_addAndFetch(index, delta)
}

public fun AtomicIntegerArray.fetchAndIncrementAt(index: Int): Int = fetchAndAddAt(index, 1)

public fun AtomicIntegerArray.incrementAndFetchAt(index: Int): Int = addAndFetchAt(index, 1)

public fun AtomicIntegerArray.fetchAndDecrementAt(index: Int): Int = fetchAndAddAt(index, -1)

public fun AtomicIntegerArray.decrementAndFetchAt(index: Int): Int = addAndFetchAt(index, -1)

public class AtomicIntegerArray private constructor() {
    public fun length(): Int = size

    public operator fun get(index: Int): Int = loadAt(index)

    public operator fun set(index: Int, newValue: Int): Unit = storeAt(index, newValue)

    public fun getAndSet(index: Int, newValue: Int): Int = exchangeAt(index, newValue)

    public fun lazySet(index: Int, newValue: Int): Unit = storeAt(index, newValue)

    public fun compareAndSet(index: Int, expectedValue: Int, update: Int): Boolean =
        compareAndSetAt(index, expectedValue, update)

    public fun weakCompareAndSet(index: Int, expectedValue: Int, update: Int): Boolean =
        compareAndSet(index, expectedValue, update)

    public fun getAndAdd(index: Int, delta: Int): Int = fetchAndAddAt(index, delta)

    public fun addAndGet(index: Int, delta: Int): Int = addAndFetchAt(index, delta)

    public fun incrementAndGet(index: Int): Int = incrementAndFetchAt(index)

    public fun getAndIncrement(index: Int): Int = fetchAndIncrementAt(index)

    public fun decrementAndGet(index: Int): Int = decrementAndFetchAt(index)

    public fun getAndDecrement(index: Int): Int = fetchAndDecrementAt(index)

    public fun getAndUpdate(index: Int, transform: (Int) -> Int): Int {
        while (true) {
            val old = loadAt(index)
            val newValue = transform(old)
            if (compareAndSetAt(index, old, newValue)) return old
        }
    }

    public fun updateAndGet(index: Int, transform: (Int) -> Int): Int {
        while (true) {
            val old = loadAt(index)
            val newValue = transform(old)
            if (compareAndSetAt(index, old, newValue)) return newValue
        }
    }

    public fun getAndAccumulate(index: Int, x: Int, accumulator: (Int, Int) -> Int): Int {
        while (true) {
            val old = loadAt(index)
            val newValue = accumulator(old, x)
            if (compareAndSetAt(index, old, newValue)) return old
        }
    }

    public fun accumulateAndGet(index: Int, x: Int, accumulator: (Int, Int) -> Int): Int {
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
