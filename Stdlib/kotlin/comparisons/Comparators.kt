package kotlin.comparisons

// MIGRATION-COMP-001
// Comparator factory and composition functions.
// Migration source: Sources/Runtime/RuntimeComparator.swift
//   kk_comparator_from_selector, kk_comparator_from_selector_descending,
//   kk_comparator_from_comparator_selector, kk_comparator_from_comparator_selector_descending,
//   kk_comparator_natural_order, kk_comparator_reverse_order,
//   kk_comparator_reversed,
//   kk_comparator_then_by, kk_comparator_then_by_descending,
//   kk_comparator_then_descending, kk_comparator_then_comparator,
//   kk_comparator_then_by_comparator_selector,
//   kk_comparator_then_by_descending_comparator_selector
//
// NOTE: Not yet wired into the compiler pipeline.
// Sema stubs in HeaderHelpers+SyntheticComparatorStubs.swift set external link
// names so all call sites dispatch directly to the kk_comparator_* ABI functions.
// This file is the migration target; wiring (and removal of those stubs) happens
// in a future RF-STDLIB task once Comparator SAM dispatch is fully supported in
// bundled Kotlin source.
//
// "thenComparing" in the MIGRATION-COMP-001 TODO corresponds to the KSwiftK-specific
// API surface: thenComparator (takes (T, T) -> Int) and thenDescending (takes (T, T) -> Int).

// ─── Internal helpers ─────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
private fun compareNullable(a: Comparable<*>?, b: Comparable<*>?): Int {
    if (a === null && b === null) return 0
    if (a === null) return -1
    if (b === null) return 1
    return (a as Comparable<Any?>).compareTo(b)
}

// ─── compareBy ───────────────────────────────────────────────────────────────

public fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T> =
    Comparator { a, b -> compareNullable(selector(a), selector(b)) }

public fun <T, K> compareBy(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    Comparator { a, b -> comparator.compare(selector(a), selector(b)) }

// ─── compareByDescending ─────────────────────────────────────────────────────

public fun <T> compareByDescending(selector: (T) -> Comparable<*>?): Comparator<T> =
    Comparator { a, b -> compareNullable(selector(b), selector(a)) }

public fun <T, K> compareByDescending(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    Comparator { a, b -> comparator.compare(selector(b), selector(a)) }

// ─── naturalOrder / reverseOrder ─────────────────────────────────────────────

public fun <T : Comparable<T>> naturalOrder(): Comparator<T> =
    Comparator { a, b -> a.compareTo(b) }

public fun <T : Comparable<T>> reverseOrder(): Comparator<T> =
    Comparator { a, b -> b.compareTo(a) }

// ─── Comparator<T>.reversed ──────────────────────────────────────────────────

public fun <T> Comparator<T>.reversed(): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r == 0) 0 else -r
    }
}

// ─── Comparator<T>.thenBy ────────────────────────────────────────────────────

public fun <T> Comparator<T>.thenBy(selector: (T) -> Comparable<*>?): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else compareNullable(selector(a), selector(b))
    }
}

public fun <T, K> Comparator<T>.thenBy(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else comparator.compare(selector(a), selector(b))
    }
}

// ─── Comparator<T>.thenByDescending ──────────────────────────────────────────

public fun <T> Comparator<T>.thenByDescending(selector: (T) -> Comparable<*>?): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else compareNullable(selector(b), selector(a))
    }
}

public fun <T, K> Comparator<T>.thenByDescending(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else comparator.compare(selector(b), selector(a))
    }
}

// ─── Comparator<T>.thenDescending / thenComparator ───────────────────────────
// "thenComparing" in MIGRATION-COMP-001 refers to these two KSwiftK-specific APIs.

public fun <T> Comparator<T>.thenDescending(comparator: (T, T) -> Int): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else {
            val r2 = comparator(a, b)
            if (r2 == 0) 0 else -r2
        }
    }
}

public fun <T> Comparator<T>.thenComparator(comparison: (T, T) -> Int): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else comparison(a, b)
    }
}
