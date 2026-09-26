@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

// MIGRATION-ATOMIC-002
// AtomicIntArray / AtomicLongArray / AtomicArray<T> CAS-loop update operators
// migrated to Kotlin source (KSP-CAP-004 / KSP-673). They are CAS retry loops
// built on the loadAt/compareAndSetAt bridge members.
// Migration source: Sources/Runtime/RuntimeAtomic.swift
//   kk_atomic_int_array_*/kk_atomic_long_array_*/kk_atomic_ref_array_*

// ── AtomicIntArray ─────────────────────────────────────────────────────────

public fun AtomicIntArray.fetchAndUpdateAt(index: Int, transform: (Int) -> Int): Int {
    while (true) {
        val old = loadAt(index)
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

// ── AtomicLongArray ────────────────────────────────────────────────────────

public fun AtomicLongArray.fetchAndUpdateAt(index: Int, transform: (Long) -> Long): Long {
    while (true) {
        val old = loadAt(index)
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

// ── AtomicArray<T> ─────────────────────────────────────────────────────────
// The residual loadAt bridge models an initially-null element and returns the
// nullable element type, so the loaded slot is cast to T before the transform;
// this matches the stdlib contract where AtomicArray<T> slots are T-typed.

public fun <T> AtomicArray<T>.fetchAndUpdateAt(index: Int, transform: (T) -> T): T {
    while (true) {
        val old = loadAt(index) as T
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

public fun <T> AtomicArray<T>.updateAt(index: Int, transform: (T) -> T): Unit {
    while (true) {
        val old = loadAt(index) as T
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return
    }
}

public fun <T> AtomicArray<T>.updateAndFetchAt(index: Int, transform: (T) -> T): T {
    while (true) {
        val old = loadAt(index) as T
        val newValue = transform(old)
        if (compareAndSetAt(index, old, newValue)) return newValue
    }
}
