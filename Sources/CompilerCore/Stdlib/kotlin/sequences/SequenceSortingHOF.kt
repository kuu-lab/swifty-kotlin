package kotlin.sequences

import kotlin.comparisons.naturalOrder
import kotlin.internal.mergeSortWith

// MIGRATION-SEQ-005
// Sequence sorting HOFs migrated to Kotlin source.
// Kept in a separate file with package kotlin.sequences to avoid FQ-name collisions
// with the List sorting extensions in kotlin.collections/ListSortingHOF.kt.
//
// Migration source:
//   Sources/Runtime/RuntimeSequence.swift
//
// Migrated: sorted, sortedBy, sortedByDescending, sortedDescending, sortedWith

public fun <T : Comparable<T>> Sequence<T>.sorted(): Sequence<T> {
    val result = this.toMutableList()
    result.mergeSortWith(naturalOrder())
    return result.asSequence()
}

public fun <T, R : Comparable<R>> Sequence<T>.sortedBy(selector: (T) -> R): Sequence<T> {
    val decorated = mutableListOf<Pair<R, T>>()
    for (element in this) {
        decorated.add(Pair(selector(element), element))
    }
    decorated.mergeSortWith(Comparator<Pair<R, T>> { a, b -> a.first.compareTo(b.first) })
    val result = mutableListOf<T>()
    for (pair in decorated) {
        result.add(pair.second)
    }
    return result.asSequence()
}

public fun <T, R : Comparable<R>> Sequence<T>.sortedByDescending(selector: (T) -> R): Sequence<T> {
    val decorated = mutableListOf<Pair<R, T>>()
    for (element in this) {
        decorated.add(Pair(selector(element), element))
    }
    decorated.mergeSortWith(Comparator<Pair<R, T>> { a, b -> b.first.compareTo(a.first) })
    val result = mutableListOf<T>()
    for (pair in decorated) {
        result.add(pair.second)
    }
    return result.asSequence()
}

public fun <T : Comparable<T>> Sequence<T>.sortedDescending(): Sequence<T> =
    sorted().reversed().asSequence()

public fun <T> Sequence<T>.sortedWith(comparator: Comparator<in T>): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        var sorted: MutableList<T>? = null

        override fun iterator(): Iterator<T> {
            val existing = sorted
            if (existing != null) {
                return existing.iterator()
            }
            val fresh = source.toMutableList()
            fresh.mergeSortWith(comparator)
            sorted = fresh
            return fresh.iterator()
        }
    }
}
