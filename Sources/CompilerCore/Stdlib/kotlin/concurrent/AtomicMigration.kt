package kotlin.concurrent

import java.util.concurrent.atomic.AtomicInteger

// MIGRATION-ATOMIC-001
// AtomicInt / AtomicLong / AtomicBoolean / AtomicReference API migrated to
// Kotlin source.
// get/set/getAndSet delegate to load/store/exchange bridge members;
// incrementAndGet/decrementAndGet/addAndGet delegate to the
// incrementAndFetch/decrementAndFetch/addAndFetch bridge members.
// getAndUpdate/updateAndGet/fetchAndUpdate/updateAndFetch are CAS retry loops
// built on the load/compareAndSet bridge members (KSP-CAP-004 / KSP-673).
// java.util.concurrent.atomic.AtomicInteger shares the same kk_atomic_int_*
// bridge, so its update operators are migrated here as well.
// Migration source: Sources/Runtime/RuntimeAtomic.swift
//   kk_atomic_int_*/kk_atomic_long_*/kk_atomic_bool_*/kk_atomic_ref_*

// ── AtomicInt ──────────────────────────────────────────────────────────────

public fun AtomicInt.get(): Int = load()

public fun AtomicInt.set(value: Int): Unit = store(value)

public fun AtomicInt.getAndSet(newValue: Int): Int = exchange(newValue)

public fun AtomicInt.incrementAndGet(): Int = incrementAndFetch()

public fun AtomicInt.decrementAndGet(): Int = decrementAndFetch()

public fun AtomicInt.addAndGet(delta: Int): Int = addAndFetch(delta)

public fun AtomicInt.getAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicInt.updateAndGet(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicInt.fetchAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

// ── AtomicLong ─────────────────────────────────────────────────────────────

public fun AtomicLong.get(): Long = load()

public fun AtomicLong.set(value: Long): Unit = store(value)

public fun AtomicLong.getAndSet(newValue: Long): Long = exchange(newValue)

public fun AtomicLong.incrementAndGet(): Long = incrementAndFetch()

public fun AtomicLong.decrementAndGet(): Long = decrementAndFetch()

public fun AtomicLong.addAndGet(delta: Long): Long = addAndFetch(delta)

public fun AtomicLong.getAndUpdate(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicLong.updateAndGet(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicLong.fetchAndUpdate(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

// ── AtomicBoolean ──────────────────────────────────────────────────────────

public fun AtomicBoolean.getAndUpdate(transform: (Boolean) -> Boolean): Boolean {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicBoolean.updateAndGet(transform: (Boolean) -> Boolean): Boolean {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicBoolean.fetchAndUpdate(transform: (Boolean) -> Boolean): Boolean {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

// ── AtomicReference<T> ─────────────────────────────────────────────────────

public fun <T> AtomicReference<T>.get(): T = load()

public fun <T> AtomicReference<T>.set(value: T): Unit = store(value)

public fun <T> AtomicReference<T>.getAndSet(newValue: T): T = exchange(newValue)

public fun <T> AtomicReference<T>.getAndUpdate(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun <T> AtomicReference<T>.updateAndGet(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun <T> AtomicReference<T>.fetchAndUpdate(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun <T> AtomicReference<T>.updateAndFetch(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

// ── java.util.concurrent.atomic.AtomicInteger ──────────────────────────────

public fun AtomicInteger.getAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicInteger.updateAndGet(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicInteger.fetchAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}
