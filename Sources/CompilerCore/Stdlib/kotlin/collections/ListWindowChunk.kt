package kotlin.collections

// MIGRATION-COL-009
// List window/chunk HOFs migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
// Functions: chunked, windowed, zipWithNext, zip, withIndex
//
// NOTE: Not yet wired into the compiler pipeline.
// The Sema layer (HeaderHelpers+SyntheticListTransformMembers.swift,
// HeaderHelpers+SyntheticListAggregateMembers.swift,
// HeaderHelpers+SyntheticListIndexedAndArrayDequeStubs.swift) still synthesises
// stubs that route these call sites to kk_* ABI functions. This file is the
// migration target; wiring (and removal of synthetic stubs) happens in a
// follow-up RF-STDLIB task.

// ── chunked ──────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Iterable<T>.chunked(size: Int): List<List<T>>
// ABI counterpart: kk_list_chunked, kk_list_chunked_transform

public fun <T> Iterable<T>.chunked(size: Int): List<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    val result = mutableListOf<List<T>>()
    var chunk = mutableListOf<T>()
    for (element in this) {
        chunk.add(element)
        if (chunk.size == size) {
            result.add(chunk)
            chunk = mutableListOf()
        }
    }
    if (chunk.size > 0) result.add(chunk)
    return result
}

public fun <T, R> Iterable<T>.chunked(size: Int, transform: (List<T>) -> R): List<R> {
    require(size > 0) { "size must be positive, but was $size" }
    val result = mutableListOf<R>()
    var chunk = mutableListOf<T>()
    for (element in this) {
        chunk.add(element)
        if (chunk.size == size) {
            result.add(transform(chunk))
            chunk = mutableListOf()
        }
    }
    if (chunk.size > 0) result.add(transform(chunk))
    return result
}

// ── windowed ─────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> List<T>.windowed(size, step, partialWindows): List<List<T>>
// ABI counterparts: kk_list_windowed_default, kk_list_windowed,
//                   kk_list_windowed_partial, kk_list_windowed_transform
//
// Receiver is List<T> (not Iterable<T>) because windowed requires random-access
// indexing to slice sub-lists efficiently. Real Kotlin stdlib matches this.

public fun <T> List<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): List<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    val result = mutableListOf<List<T>>()
    var i = 0
    while (i < this.size) {
        val end = if (i + size <= this.size) i + size else this.size
        if (end - i == size || partialWindows) {
            val window = mutableListOf<T>()
            var j = i
            while (j < end) {
                window.add(this[j])
                j++
            }
            result.add(window)
        }
        i += step
    }
    return result
}

public fun <T, R> List<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (List<T>) -> R
): List<R> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    val result = mutableListOf<R>()
    var i = 0
    while (i < this.size) {
        val end = if (i + size <= this.size) i + size else this.size
        if (end - i == size || partialWindows) {
            val window = mutableListOf<T>()
            var j = i
            while (j < end) {
                window.add(this[j])
                j++
            }
            result.add(transform(window))
        }
        i += step
    }
    return result
}

// ── zipWithNext ──────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Iterable<T>.zipWithNext(): List<Pair<T, T>>
// ABI counterparts: kk_list_zipWithNext, kk_list_zipWithNextTransform
//
// Uses an iterator pair (current/next) to avoid allocating an intermediate
// list — matches the behaviour of the ABI implementation in
// RuntimeCollectionHOF.swift kk_list_zipWithNext.

public fun <T> Iterable<T>.zipWithNext(): List<Pair<T, T>> {
    val iter = iterator()
    if (!iter.hasNext()) return emptyList()
    val result = mutableListOf<Pair<T, T>>()
    var current = iter.next()
    while (iter.hasNext()) {
        val next = iter.next()
        result.add(Pair(current, next))
        current = next
    }
    return result
}

public fun <T, R> Iterable<T>.zipWithNext(transform: (T, T) -> R): List<R> {
    val iter = iterator()
    if (!iter.hasNext()) return emptyList()
    val result = mutableListOf<R>()
    var current = iter.next()
    while (iter.hasNext()) {
        val next = iter.next()
        result.add(transform(current, next))
        current = next
    }
    return result
}

// ── zip ──────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T, R> Iterable<T>.zip(other: Iterable<R>): List<Pair<T, R>>
// ABI counterpart: kk_list_zip
//
// Result length equals the shorter of the two iterables, matching Kotlin
// stdlib and the Swift ABI implementation (min(lhs.count, rhs.count)).

public fun <T, R> Iterable<T>.zip(other: Iterable<R>): List<Pair<T, R>> {
    val result = mutableListOf<Pair<T, R>>()
    val iter1 = this.iterator()
    val iter2 = other.iterator()
    while (iter1.hasNext() && iter2.hasNext()) {
        result.add(Pair(iter1.next(), iter2.next()))
    }
    return result
}

public fun <T, R, V> Iterable<T>.zip(other: Iterable<R>, transform: (T, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val iter1 = this.iterator()
    val iter2 = other.iterator()
    while (iter1.hasNext() && iter2.hasNext()) {
        result.add(transform(iter1.next(), iter2.next()))
    }
    return result
}

// ── withIndex ────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Iterable<T>.withIndex(): Iterable<IndexedValue<T>>
// ABI counterpart: kk_list_withIndex
//
// NOTE: Wiring this function requires IndexedValue<T> to be available as a
// compiled Kotlin type (currently only registered as a synthetic stub via
// registerSyntheticIndexedValueStub in
// HeaderHelpers+SyntheticListIndexedAndArrayDequeStubs.swift).

public fun <T> Iterable<T>.withIndex(): Iterable<IndexedValue<T>> {
    val result = mutableListOf<IndexedValue<T>>()
    var index = 0
    for (element in this) {
        result.add(IndexedValue(index, element))
        index++
    }
    return result
}
