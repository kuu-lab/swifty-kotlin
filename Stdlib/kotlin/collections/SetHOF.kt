package kotlin.collections

// MIGRATION-COL-013
// Set higher-order and terminal helpers migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift       (kk_set_filter, kk_set_map,
//     kk_set_flatMap, kk_set_forEach, kk_set_count_predicate, kk_set_any,
//     kk_set_all, kk_set_none)
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift (kk_set_sorted)
//   Sources/Runtime/RuntimeSetAndMap.swift           (kk_set_first, kk_set_last)
//
// NOTE: Some call sites are still routed through synthetic member fallbacks and
// ABI lowering. These definitions are the Kotlin-source migration target used
// by the bundled stdlib injection path; full dispatch rewiring follows in the
// RF-STDLIB lowering cleanup.

public fun <T> Set<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) {
            result.add(element)
        }
    }
    return result
}

public fun <T, R> Set<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        result.add(transform(element))
    }
    return result
}

public fun <T, R> Set<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        for (item in transform(element)) {
            result.add(item)
        }
    }
    return result
}

public fun <T> Set<T>.forEach(action: (T) -> Unit) {
    for (element in this) {
        action(element)
    }
}

public fun <T : Comparable<T>> Set<T>.sorted(): List<T> {
    return this.toList().sorted()
}

public fun <T> Set<T>.first(): T {
    val iter = this.iterator()
    if (!iter.hasNext()) {
        throw NoSuchElementException("Collection is empty.")
    }
    return iter.next()
}

public fun <T> Set<T>.last(): T {
    val iter = this.iterator()
    if (!iter.hasNext()) {
        throw NoSuchElementException("Collection is empty.")
    }
    var result = iter.next()
    while (iter.hasNext()) {
        result = iter.next()
    }
    return result
}

public fun <T> Set<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    for (element in this) {
        if (predicate(element)) {
            count++
        }
    }
    return count
}

public fun <T> Set<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) {
            return true
        }
    }
    return false
}

public fun <T> Set<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) {
            return false
        }
    }
    return true
}

public fun <T> Set<T>.none(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) {
            return false
        }
    }
    return true
}
