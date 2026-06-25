package kotlin.sequences

// MIGRATION-SEQ-005
// Sequence window/limiting HOFs migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSequence.swift
// Functions: take, takeWhile, drop, dropWhile, chunked, windowed,
//            zip, zipWithNext, distinct, distinctBy
//
// NOTE: Not yet wired into the compiler pipeline.
// The Sema layer (HeaderHelpers+SyntheticSequenceTerminalStubs.swift,
// HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift) still synthesises
// stubs that route these call sites to kk_* ABI functions. This file is the
// migration target; wiring (and removal of synthetic stubs) happens in a
// follow-up RF-STDLIB task.

// ── take ──────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Sequence<T>.take(n: Int): Sequence<T>
// ABI counterpart: kk_sequence_take
//
// Returns a lazy sequence containing the first n elements.
// Throws IllegalArgumentException if n < 0.

public fun <T> Sequence<T>.take(n: Int): Sequence<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    return sequence {
        var count = 0
        val iter = this@take.iterator()
        while (count < n && iter.hasNext()) {
            yield(iter.next())
            count++
        }
    }
}

// ── takeWhile ─────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Sequence<T>.takeWhile(predicate: (T) -> Boolean): Sequence<T>
// ABI counterpart: kk_sequence_takeWhile
//
// Returns a lazy sequence containing elements as long as the predicate returns true.
// Stops at the first element that does not satisfy the predicate.

public fun <T> Sequence<T>.takeWhile(predicate: (T) -> Boolean): Sequence<T> {
    return sequence {
        var yielding = true
        val iter = this@takeWhile.iterator()
        while (yielding && iter.hasNext()) {
            val element = iter.next()
            if (predicate(element)) {
                yield(element)
            } else {
                yielding = false
            }
        }
    }
}

// ── drop ──────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Sequence<T>.drop(n: Int): Sequence<T>
// ABI counterpart: kk_sequence_drop
//
// Returns a lazy sequence that skips the first n elements.
// Throws IllegalArgumentException if n < 0.

public fun <T> Sequence<T>.drop(n: Int): Sequence<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    return sequence {
        var skipped = 0
        val iter = this@drop.iterator()
        while (iter.hasNext()) {
            val element = iter.next()
            if (skipped >= n) {
                yield(element)
            } else {
                skipped++
            }
        }
    }
}

// ── dropWhile ─────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Sequence<T>.dropWhile(predicate: (T) -> Boolean): Sequence<T>
// ABI counterpart: kk_sequence_dropWhile
//
// Returns a lazy sequence that skips elements as long as the predicate returns true,
// then yields all remaining elements.

public fun <T> Sequence<T>.dropWhile(predicate: (T) -> Boolean): Sequence<T> {
    return sequence {
        var dropping = true
        val iter = this@dropWhile.iterator()
        while (iter.hasNext()) {
            val element = iter.next()
            if (dropping && predicate(element)) {
                // skip
            } else {
                dropping = false
                yield(element)
            }
        }
    }
}

// ── chunked ───────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Sequence<T>.chunked(size: Int): Sequence<List<T>>
// ABI counterpart: kk_sequence_chunked
//
// Splits a sequence into lists each not exceeding the given size.
// The last list may be shorter if the sequence size is not divisible by size.

public fun <T> Sequence<T>.chunked(size: Int): Sequence<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    return sequence {
        var chunk = mutableListOf<T>()
        for (element in this@chunked) {
            chunk.add(element)
            if (chunk.size == size) {
                yield(chunk)
                chunk = mutableListOf()
            }
        }
        if (chunk.size > 0) yield(chunk)
    }
}

public fun <T, R> Sequence<T>.chunked(size: Int, transform: (List<T>) -> R): Sequence<R> {
    require(size > 0) { "size must be positive, but was $size" }
    return sequence {
        var chunk = mutableListOf<T>()
        for (element in this@chunked) {
            chunk.add(element)
            if (chunk.size == size) {
                yield(transform(chunk))
                chunk = mutableListOf()
            }
        }
        if (chunk.size > 0) yield(transform(chunk))
    }
}

// ── windowed ──────────────────────────────────────────────────────────────────
//
// Kotlin stdlib:
//   fun <T> Sequence<T>.windowed(size, step, partialWindows): Sequence<List<T>>
// ABI counterpart: kk_sequence_windowed
//
// Returns a lazy sequence of sliding windows of the given size, advancing by step
// each time. Collects elements eagerly so random-access indexing is available.

public fun <T> Sequence<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): Sequence<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    return sequence {
        val elements = mutableListOf<T>()
        for (element in this@windowed) { elements.add(element) }
        var i = 0
        while (i < elements.size) {
            val end = if (i + size <= elements.size) i + size else elements.size
            if (end - i == size || partialWindows) {
                val window = mutableListOf<T>()
                var j = i
                while (j < end) {
                    window.add(elements[j])
                    j++
                }
                yield(window)
            }
            i += step
        }
    }
}

public fun <T, R> Sequence<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (List<T>) -> R
): Sequence<R> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    return sequence {
        val elements = mutableListOf<T>()
        for (element in this@windowed) { elements.add(element) }
        var i = 0
        while (i < elements.size) {
            val end = if (i + size <= elements.size) i + size else elements.size
            if (end - i == size || partialWindows) {
                val window = mutableListOf<T>()
                var j = i
                while (j < end) {
                    window.add(elements[j])
                    j++
                }
                yield(transform(window))
            }
            i += step
        }
    }
}

// ── zip ───────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T, R> Sequence<T>.zip(other: Sequence<R>): Sequence<Pair<T, R>>
// ABI counterpart: kk_sequence_zip
//
// Merges two sequences into a sequence of pairs. The result length equals
// the shorter of the two sequences.

public fun <T, R> Sequence<T>.zip(other: Sequence<R>): Sequence<Pair<T, R>> {
    return sequence {
        val iter1 = this@zip.iterator()
        val iter2 = other.iterator()
        while (iter1.hasNext() && iter2.hasNext()) {
            yield(Pair(iter1.next(), iter2.next()))
        }
    }
}

public fun <T, R, V> Sequence<T>.zip(other: Sequence<R>, transform: (T, R) -> V): Sequence<V> {
    return sequence {
        val iter1 = this@zip.iterator()
        val iter2 = other.iterator()
        while (iter1.hasNext() && iter2.hasNext()) {
            yield(transform(iter1.next(), iter2.next()))
        }
    }
}

// ── zipWithNext ───────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Sequence<T>.zipWithNext(): Sequence<Pair<T, T>>
// ABI counterparts: kk_sequence_zipWithNext, kk_sequence_zipWithNextTransform
//
// Returns a lazy sequence of pairs of adjacent elements.
// An empty or single-element sequence produces an empty result.

public fun <T> Sequence<T>.zipWithNext(): Sequence<Pair<T, T>> {
    return sequence {
        val iter = this@zipWithNext.iterator()
        if (iter.hasNext()) {
            var current = iter.next()
            while (iter.hasNext()) {
                val next = iter.next()
                yield(Pair(current, next))
                current = next
            }
        }
    }
}

public fun <T, R> Sequence<T>.zipWithNext(transform: (T, T) -> R): Sequence<R> {
    return sequence {
        val iter = this@zipWithNext.iterator()
        if (iter.hasNext()) {
            var current = iter.next()
            while (iter.hasNext()) {
                val next = iter.next()
                yield(transform(current, next))
                current = next
            }
        }
    }
}

// ── distinct ──────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Sequence<T>.distinct(): Sequence<T>
// ABI counterpart: kk_sequence_distinct
//
// Returns a lazy sequence containing only distinct elements.
// Uses structural equality (==) for comparison and tracks seen elements
// using a list to preserve encounter order.

public fun <T> Sequence<T>.distinct(): Sequence<T> {
    return sequence {
        val seen = mutableListOf<T>()
        for (element in this@distinct) {
            if (!seen.contains(element)) {
                seen.add(element)
                yield(element)
            }
        }
    }
}

// ── distinctBy ────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T, K> Sequence<T>.distinctBy(selector: (T) -> K): Sequence<T>
// ABI counterpart: kk_sequence_distinctBy
//
// Returns a lazy sequence containing only elements with distinct keys as
// returned by the selector function. When two elements have the same key,
// the first one encountered is yielded.

public fun <T, K> Sequence<T>.distinctBy(selector: (T) -> K): Sequence<T> {
    return sequence {
        val keys = mutableListOf<K>()
        for (element in this@distinctBy) {
            val key = selector(element)
            if (!keys.contains(key)) {
                keys.add(key)
                yield(element)
            }
        }
    }
}
