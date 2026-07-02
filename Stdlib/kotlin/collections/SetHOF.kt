package kotlin.collections

// MIGRATION-COL-013
// Set higher-order function extension functions migrated from Swift Runtime.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift
//     kk_set_filter          (line ~2990)
//     kk_set_map             (line ~2973)
//     kk_set_flatMap         (line ~3051)
//     kk_set_forEach         (line ~3006)
//     kk_set_any             (line ~3105)
//     kk_set_none            (line ~3120)
//     kk_set_all             (line ~3135)
//     kk_set_count_predicate (line ~3147)
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift
//     kk_set_sorted          (line ~513)
//   Sources/Runtime/RuntimeSetAndMap.swift
//     kk_set_first / kk_set_last (line ~106 / ~128)
//
// filter / map / flatMap / sorted are also covered by Iterable<T> extensions in
// CollectionHOF.kt (MIGRATION-COL-002), ListFilterHOF.kt (MIGRATION-COL-003), and
// ListSortOrdering.kt (MIGRATION-COL-006). Set-specific overloads are provided here
// to give the compiler a direct dispatch target when the pipeline is wired (RF-STDLIB-004+).
//
// NOTE: Not yet wired into the compiler pipeline.
// HOF call sites on Set are intercepted by the lowering passes and rewritten to
// kk_set_* ABI calls. This file is the migration target; wiring (and removal of the
// corresponding kk_set_* entries) happens in RF-STDLIB-004+.

// ─── filter ──────────────────────────────────────────────────────────────────

public fun <T> Set<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    return result
}

// ─── map ─────────────────────────────────────────────────────────────────────

public fun <T, R> Set<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        result.add(transform(element))
    }
    return result
}

// ─── flatMap ─────────────────────────────────────────────────────────────────

public fun <T, R> Set<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        for (subElement in transform(element)) {
            result.add(subElement)
        }
    }
    return result
}

// ─── forEach ─────────────────────────────────────────────────────────────────

public fun <T> Set<T>.forEach(action: (T) -> Unit) {
    for (element in this) {
        action(element)
    }
}

// ─── sorted ──────────────────────────────────────────────────────────────────
// Returns a List<T> with elements sorted in natural ascending order.
// Delegates to Iterable<T>.sortedWith (ListSortOrdering.kt, MIGRATION-COL-006).

public fun <T : Comparable<T>> Set<T>.sorted(): List<T> =
    sortedWith(Comparator { a, b -> a.compareTo(b) })

// ─── first ───────────────────────────────────────────────────────────────────

public fun <T> Set<T>.first(): T {
    val iter = iterator()
    if (!iter.hasNext()) throw NoSuchElementException("Collection is empty.")
    return iter.next()
}

public fun <T> Set<T>.first(predicate: (T) -> Boolean): T {
    for (element in this) {
        if (predicate(element)) return element
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

// ─── last ────────────────────────────────────────────────────────────────────

public fun <T> Set<T>.last(): T {
    val iter = iterator()
    if (!iter.hasNext()) throw NoSuchElementException("Collection is empty.")
    var last = iter.next()
    while (iter.hasNext()) {
        last = iter.next()
    }
    return last
}

public fun <T> Set<T>.last(predicate: (T) -> Boolean): T {
    var found = false
    var last: Any? = null
    for (element in this) {
        if (predicate(element)) {
            last = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    @Suppress("UNCHECKED_CAST")
    return last as T
}

// ─── count ───────────────────────────────────────────────────────────────────

public fun <T> Set<T>.count(): Int = size

public fun <T> Set<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    for (element in this) {
        if (predicate(element)) count++
    }
    return count
}

// ─── any ─────────────────────────────────────────────────────────────────────

public fun <T> Set<T>.any(): Boolean = size != 0

public fun <T> Set<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return true
    }
    return false
}

// ─── all ─────────────────────────────────────────────────────────────────────

public fun <T> Set<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) return false
    }
    return true
}

// ─── none ────────────────────────────────────────────────────────────────────

public fun <T> Set<T>.none(): Boolean = size == 0

public fun <T> Set<T>.none(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return false
    }
    return true
}
