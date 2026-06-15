package kotlin.collections

// MIGRATION-COL-010
// List partial retrieval HOF — pure Kotlin implementations.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift  (take / takeLast / drop / dropLast / distinct / distinctBy)
//   Sources/Runtime/RuntimeCollectionHOF.swift         (takeWhile / dropWhile / takeLastWhile / dropLastWhile)
//
// NOTE: Not yet wired into the compiler pipeline.
// Sema stubs (HeaderHelpers+SyntheticListTransformMembers.swift,
// HeaderHelpers+SyntheticListAggregateMembers.swift) still dispatch
// all call sites directly to the corresponding kk_list_* runtime functions.
// This file is the migration target; wiring (and removal of those stubs)
// happens in RF-STDLIB-004+.

// ─── take / takeLast ─────────────────────────────────────────────────────────

public fun <T> List<T>.take(n: Int): List<T> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return emptyList()
    val sz = size
    if (n >= sz) return toList()
    val result = mutableListOf<T>()
    var i = 0
    while (i < n) {
        result.add(get(i))
        i++
    }
    return result
}

public fun <T> List<T>.takeLast(n: Int): List<T> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return emptyList()
    val sz = size
    if (n >= sz) return toList()
    val result = mutableListOf<T>()
    val start = sz - n
    var i = start
    while (i < sz) {
        result.add(get(i))
        i++
    }
    return result
}

// ─── drop / dropLast ─────────────────────────────────────────────────────────

public fun <T> List<T>.drop(n: Int): List<T> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val sz = size
    if (n >= sz) return emptyList()
    val result = mutableListOf<T>()
    var i = n
    while (i < sz) {
        result.add(get(i))
        i++
    }
    return result
}

public fun <T> List<T>.dropLast(n: Int): List<T> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val sz = size
    if (n >= sz) return emptyList()
    val keepCount = sz - n
    val result = mutableListOf<T>()
    var i = 0
    while (i < keepCount) {
        result.add(get(i))
        i++
    }
    return result
}

// ─── takeWhile / dropWhile ───────────────────────────────────────────────────

public fun <T> List<T>.takeWhile(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = get(i)
        if (!predicate(element)) break
        result.add(element)
        i++
    }
    return result
}

public fun <T> List<T>.dropWhile(predicate: (T) -> Boolean): List<T> {
    var i = 0
    val sz = size
    while (i < sz && predicate(get(i))) {
        i++
    }
    if (i >= sz) return emptyList()
    val result = mutableListOf<T>()
    while (i < sz) {
        result.add(get(i))
        i++
    }
    return result
}

// ─── takeLastWhile / dropLastWhile ───────────────────────────────────────────

public fun <T> List<T>.takeLastWhile(predicate: (T) -> Boolean): List<T> {
    val sz = size
    var i = sz - 1
    while (i >= 0 && predicate(get(i))) {
        i--
    }
    // i is the last index where predicate was false; elements from (i+1) to (sz-1)
    val start = i + 1
    if (start >= sz) return emptyList()
    val result = mutableListOf<T>()
    var j = start
    while (j < sz) {
        result.add(get(j))
        j++
    }
    return result
}

public fun <T> List<T>.dropLastWhile(predicate: (T) -> Boolean): List<T> {
    val sz = size
    var i = sz - 1
    while (i >= 0 && predicate(get(i))) {
        i--
    }
    // elements from 0 to i (inclusive) are kept
    if (i < 0) return emptyList()
    val result = mutableListOf<T>()
    var j = 0
    while (j <= i) {
        result.add(get(j))
        j++
    }
    return result
}

// ─── distinct / distinctBy ───────────────────────────────────────────────────

public fun <T> List<T>.distinct(): List<T> {
    val seen = mutableSetOf<T>()
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = get(i)
        if (seen.add(element)) {
            result.add(element)
        }
        i++
    }
    return result
}

public fun <T, K> List<T>.distinctBy(selector: (T) -> K): List<T> {
    val seenKeys = mutableSetOf<K>()
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = get(i)
        val key = selector(element)
        if (seenKeys.add(key)) {
            result.add(element)
        }
        i++
    }
    return result
}
