package kotlin.concurrent

// MIGRATION-ATOMIC-001
// AtomicInt / AtomicLong / AtomicReference API migrated to Kotlin source.
// Primitive CAS (compareAndSet) is delegated to the bridge; all higher-level
// operations are implemented as Kotlin CAS loops.
// Migration source: Sources/Runtime/RuntimeAtomic.swift
//   kk_atomic_int_*/kk_atomic_long_*/kk_atomic_ref_*

// ── AtomicInt ──────────────────────────────────────────────────────────────

public fun AtomicInt.get(): Int = load()

public fun AtomicInt.set(value: Int): Unit = store(value)

public fun AtomicInt.getAndSet(newValue: Int): Int = exchange(newValue)

public fun AtomicInt.incrementAndGet(): Int {
    while (true) {
        val old = load()
        val next = old + 1
        if (compareAndSet(old, next)) return next
    }
}

public fun AtomicInt.decrementAndGet(): Int {
    while (true) {
        val old = load()
        val next = old - 1
        if (compareAndSet(old, next)) return next
    }
}

public fun AtomicInt.addAndGet(delta: Int): Int {
    while (true) {
        val old = load()
        val next = old + delta
        if (compareAndSet(old, next)) return next
    }
}

// ── AtomicLong ─────────────────────────────────────────────────────────────

public fun AtomicLong.get(): Long = load()

public fun AtomicLong.set(value: Long): Unit = store(value)

public fun AtomicLong.getAndSet(newValue: Long): Long = exchange(newValue)

public fun AtomicLong.incrementAndGet(): Long {
    while (true) {
        val old = load()
        val next = old + 1L
        if (compareAndSet(old, next)) return next
    }
}

public fun AtomicLong.decrementAndGet(): Long {
    while (true) {
        val old = load()
        val next = old - 1L
        if (compareAndSet(old, next)) return next
    }
}

public fun AtomicLong.addAndGet(delta: Long): Long {
    while (true) {
        val old = load()
        val next = old + delta
        if (compareAndSet(old, next)) return next
    }
}

// ── AtomicReference<T> ─────────────────────────────────────────────────────

public fun <T> AtomicReference<T>.get(): T = load()

public fun <T> AtomicReference<T>.set(value: T): Unit = store(value)

public fun <T> AtomicReference<T>.getAndSet(newValue: T): T = exchange(newValue)
