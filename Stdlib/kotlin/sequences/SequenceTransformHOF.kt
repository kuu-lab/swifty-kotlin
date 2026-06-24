package kotlin.sequences

// MIGRATION-SEQ-002
// Sequence transform HOF functions migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSequence.swift
//   kk_sequence_map          (line ~1536)
//   kk_sequence_mapIndexed   (line ~1907)
//   kk_sequence_mapNotNull   (line ~1748)
//   kk_sequence_flatMap      (line ~2102)
//   kk_sequence_flatten      (line ~3735)
//   kk_sequence_filter       (line ~1549)
//   kk_sequence_filterNot    (line ~1717)
//   kk_sequence_filterNotNull (line ~1850)
//
// NOTE: Not yet wired into the compiler pipeline.
// CallLowerer+CollectionStdlibMemberCalls.swift still routes all sequence HOF
// call sites directly to the kk_sequence_* ABI functions. This file is the
// migration target; wiring (and removal of those entries in
// CallLowerer+CollectionStdlibMemberCalls.swift) happens in a follow-up task.
//
// Implementation strategy:
//   Each operation eagerly materialises the result into a MutableList, then
//   wraps it as a Sequence via the kk_sequence_from_list ABI bridge. Full lazy
//   step-chain evaluation (matching the existing Swift runtime step model) will
//   be restored in the wiring step once anonymous Sequence wrapper classes are
//   supported in bundled Kotlin source.

// ─── ABI bridge ──────────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
private external fun kk_sequence_from_list(list: List<*>): Sequence<*>

// ─── map ─────────────────────────────────────────────────────────────────────

/**
 * Returns a sequence containing the results of applying the given [transform]
 * function to each element in the original sequence.
 */
public fun <T, R> Sequence<T>.map(transform: (T) -> R): Sequence<R> {
    val result = mutableListOf<R>()
    for (element in this) result.add(transform(element))
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<R>
}

// ─── mapIndexed ──────────────────────────────────────────────────────────────

/**
 * Returns a sequence containing the results of applying the given [transform]
 * function to each element and its index in the original sequence.
 *
 * @param transform function that takes the index of an element and the element
 * itself and returns the result of the transform applied to the element.
 */
public fun <T, R> Sequence<T>.mapIndexed(transform: (index: Int, T) -> R): Sequence<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<R>
}

// ─── mapNotNull ──────────────────────────────────────────────────────────────

/**
 * Returns a sequence containing only the non-null results of applying the given
 * [transform] function to each element in the original sequence.
 */
public fun <T, R : Any> Sequence<T>.mapNotNull(transform: (T) -> R?): Sequence<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val r = transform(element)
        if (r != null) result.add(r)
    }
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<R>
}

// ─── flatMap ─────────────────────────────────────────────────────────────────

/**
 * Returns a single sequence of all elements yielded from results of [transform]
 * function being invoked on each element of the original sequence.
 *
 * The [transform] function returns an [Iterable] — because [Sequence] implements
 * [Iterable], this overload also accepts transforms that return a [Sequence].
 */
public fun <T, R> Sequence<T>.flatMap(transform: (T) -> Iterable<R>): Sequence<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        for (sub in transform(element)) result.add(sub)
    }
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<R>
}

// ─── flatten ─────────────────────────────────────────────────────────────────

/**
 * Returns a sequence of all elements from all iterables in this sequence.
 *
 * Because [Sequence] implements [Iterable], this overload handles both
 * `Sequence<List<T>>` and `Sequence<Sequence<T>>`.
 */
public fun <T> Sequence<Iterable<T>>.flatten(): Sequence<T> {
    val result = mutableListOf<T>()
    for (iterable in this) {
        for (element in iterable) result.add(element)
    }
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<T>
}

// ─── filter ──────────────────────────────────────────────────────────────────

/**
 * Returns a sequence containing only elements matching the given [predicate].
 */
public fun <T> Sequence<T>.filter(predicate: (T) -> Boolean): Sequence<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<T>
}

// ─── filterNot ───────────────────────────────────────────────────────────────

/**
 * Returns a sequence containing all elements not matching the given [predicate].
 */
public fun <T> Sequence<T>.filterNot(predicate: (T) -> Boolean): Sequence<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (!predicate(element)) result.add(element)
    }
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<T>
}

// ─── filterNotNull ───────────────────────────────────────────────────────────

/**
 * Returns a sequence containing all elements that are not `null`.
 */
public fun <T : Any> Sequence<T?>.filterNotNull(): Sequence<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (element != null) result.add(element)
    }
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_from_list(result) as Sequence<T>
}
