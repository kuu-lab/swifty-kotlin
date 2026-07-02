package kotlin.sequences

// MIGRATION-SEQ-003
// Sequence terminal HOF functions migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSequence.swift
//   kk_sequence_to_list, kk_sequence_toSet, kk_sequence_toMutableList,
//   kk_sequence_first, kk_sequence_firstOrNull, kk_sequence_last,
//   kk_sequence_lastOrNull, kk_sequence_single, kk_sequence_count,
//   kk_sequence_any, kk_sequence_all, kk_sequence_none
//
// Implementation strategy:
//   - toList / toSet / toMutableList: iterate via forEach (intercepted by
//     CollectionLiteralLoweringPass to kk_sequence_forEach), collect into
//     a mutable collection, return.
//   - first / firstOrNull / last / lastOrNull / single: materialize via
//     toList(), then delegate to bundled List<T> HOFs (MIGRATION-COL-005).
//   - count: materialize via toList(), return size.
//   - any() / none(): materialize via toList(), check isEmpty().
//   - any(predicate) / all(predicate) / none(predicate): materialize via
//     toList(), then delegate to bundled List<T> HOFs (MIGRATION-COL-008).
//
// NOTE: Runtime ABI entry points are intentionally kept as bridge/compatibility
// helpers while stdlib-source dispatch is rolled out incrementally.
// CollectionLiteralLoweringPass continues to intercept toList() and toSet()
// on sequence-typed expressions and rewrites them directly to kk_sequence_to_list
// / kk_sequence_toSet. These bundled definitions serve as the authoritative
// Kotlin-level source; ABI-level interception will be removed in a follow-up
// RF-STDLIB task.

// ─── Materialization ──────────────────────────────────────────────────────────

public fun <T> Sequence<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    forEach { element -> result.add(element) }
    return result
}

public fun <T> Sequence<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    forEach { element -> result.add(element) }
    return result
}

public fun <T> Sequence<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    forEach { element -> result.add(element) }
    return result
}

// ─── Element access ───────────────────────────────────────────────────────────

public fun <T> Sequence<T>.first(): T = toList().first()

public fun <T> Sequence<T>.firstOrNull(): T? = toList().firstOrNull()

public fun <T> Sequence<T>.last(): T = toList().last()

public fun <T> Sequence<T>.lastOrNull(): T? = toList().lastOrNull()

public fun <T> Sequence<T>.single(): T = toList().single()

// ─── Aggregation ──────────────────────────────────────────────────────────────

public fun <T> Sequence<T>.count(): Int = toList().size

public fun <T> Sequence<T>.any(): Boolean = !toList().isEmpty()

public fun <T> Sequence<T>.any(predicate: (T) -> Boolean): Boolean = toList().any(predicate)

public fun <T> Sequence<T>.all(predicate: (T) -> Boolean): Boolean = toList().all(predicate)

public fun <T> Sequence<T>.none(): Boolean = toList().isEmpty()

public fun <T> Sequence<T>.none(predicate: (T) -> Boolean): Boolean = toList().none(predicate)
