package kotlin.concurrent

// MIGRATION-ATOMIC-001
// AtomicInt / AtomicLong / AtomicReference API migrated to Kotlin source.
// get/set/getAndSet delegate to load/store/exchange bridge members;
// incrementAndGet/decrementAndGet/addAndGet delegate to the
// incrementAndFetch/decrementAndFetch/addAndFetch bridge members.
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

// ── AtomicLong ─────────────────────────────────────────────────────────────

public fun AtomicLong.get(): Long = load()

public fun AtomicLong.set(value: Long): Unit = store(value)

public fun AtomicLong.getAndSet(newValue: Long): Long = exchange(newValue)

public fun AtomicLong.incrementAndGet(): Long = incrementAndFetch()

public fun AtomicLong.decrementAndGet(): Long = decrementAndFetch()

public fun AtomicLong.addAndGet(delta: Long): Long = addAndFetch(delta)

// ── AtomicReference<T> ─────────────────────────────────────────────────────

public fun <T> AtomicReference<T>.get(): T = load()

public fun <T> AtomicReference<T>.set(value: T): Unit = store(value)

public fun <T> AtomicReference<T>.getAndSet(newValue: T): T = exchange(newValue)
