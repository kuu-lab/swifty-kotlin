@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

public fun AtomicIntArray.fetchAndUpdateAt(index: Int, transform: (Int) -> Int): Int {
    while (true) {
        val old = loadAt(index)
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

public fun AtomicLongArray.fetchAndUpdateAt(index: Int, transform: (Long) -> Long): Long {
    while (true) {
        val old = loadAt(index)
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

public fun <T> AtomicArray<T>.fetchAndUpdateAt(index: Int, transform: (T) -> T): T {
    while (true) {
        val old = loadAt(index)
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

public fun <T> AtomicArray<T>.updateAt(index: Int, transform: (T) -> T): Unit {
    while (true) {
        val old = loadAt(index)
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return
    }
}

public fun <T> AtomicArray<T>.updateAndFetchAt(index: Int, transform: (T) -> T): T {
    while (true) {
        val old = loadAt(index)
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return newValue
    }
}
