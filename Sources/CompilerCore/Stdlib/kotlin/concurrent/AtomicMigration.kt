package kotlin.concurrent

// MIGRATION-ATOMIC-001
// AtomicInt / AtomicLong / AtomicReference API migrated to Kotlin source.
// get/set/getAndSet delegate to load/store/exchange bridge members;
// incrementAndGet/decrementAndGet/addAndGet delegate to the
// incrementAndFetch/decrementAndFetch/addAndFetch bridge members.
// KSP-671: the fetchAnd* reverse variants and compareAndSet delegate to the
// same retained bridge members (addAndFetch/incrementAndFetch/
// decrementAndFetch/compareAndExchange). The CPU-instruction cores
// (compareAndExchange and the *Fetch arithmetic ops) stay as bridges.
// while(true) CAS loops are now supported by the type checker and can be
// added here (KSP-CAP-004 / KSP-673).
// Migration source: Sources/Runtime/RuntimeAtomic.swift
//   kk_atomic_int_*/kk_atomic_long_*/kk_atomic_ref_*

// ── AtomicInt ──────────────────────────────────────────────────────────────

public fun AtomicInt.get(): Int = load()

public fun AtomicInt.set(value: Int): Unit = store(value)

public fun AtomicInt.getAndSet(newValue: Int): Int = exchange(newValue)

public fun AtomicInt.incrementAndGet(): Int = incrementAndFetch()

public fun AtomicInt.decrementAndGet(): Int = decrementAndFetch()

public fun AtomicInt.addAndGet(delta: Int): Int = addAndFetch(delta)

public fun AtomicInt.fetchAndAdd(delta: Int): Int = addAndFetch(delta) - delta

public fun AtomicInt.fetchAndIncrement(): Int = incrementAndFetch() - 1

public fun AtomicInt.fetchAndDecrement(): Int = decrementAndFetch() + 1

public fun AtomicInt.compareAndSet(expectedValue: Int, newValue: Int): Boolean =
    compareAndExchange(expectedValue, newValue) == expectedValue

// ── AtomicLong ─────────────────────────────────────────────────────────────

public fun AtomicLong.get(): Long = load()

public fun AtomicLong.set(value: Long): Unit = store(value)

public fun AtomicLong.getAndSet(newValue: Long): Long = exchange(newValue)

public fun AtomicLong.incrementAndGet(): Long = incrementAndFetch()

public fun AtomicLong.decrementAndGet(): Long = decrementAndFetch()

public fun AtomicLong.addAndGet(delta: Long): Long = addAndFetch(delta)

public fun AtomicLong.fetchAndAdd(delta: Long): Long = addAndFetch(delta) - delta

public fun AtomicLong.fetchAndIncrement(): Long = incrementAndFetch() - 1L

public fun AtomicLong.fetchAndDecrement(): Long = decrementAndFetch() + 1L

public fun AtomicLong.compareAndSet(expectedValue: Long, newValue: Long): Boolean =
    compareAndExchange(expectedValue, newValue) == expectedValue

// ── AtomicReference<T> ─────────────────────────────────────────────────────

public fun <T> AtomicReference<T>.get(): T = load()

public fun <T> AtomicReference<T>.set(value: T): Unit = store(value)

public fun <T> AtomicReference<T>.getAndSet(newValue: T): T = exchange(newValue)
