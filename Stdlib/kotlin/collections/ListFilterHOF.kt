package kotlin.collections

// MIGRATION-COL-003
// List filter higher-order functions migrated from Swift Runtime.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//   kk_list_filter          (line ~203)
//   kk_list_filterNot       (line ~218)
//   kk_list_filterNotNull   (line ~389)
//   kk_list_filterIndexed   (line ~1791)
//   kk_list_filterIsInstance (line ~2545)
//
// NOTE: Not yet wired into the compiler pipeline.
// CollectionLiteralLoweringPass intercepts filter/filterNot/filterNotNull/
// filterIndexed/filterIsInstance call sites and rewrites them to kk_* ABI calls.
// Synthetic sema stubs for filterNot and filterIndexed live in
//   HeaderHelpers+SyntheticListTransformMembers.swift
//   HeaderHelpers+SyntheticListIndexedAndArrayDequeStubs.swift
// This file is the migration target; wiring (and removal of those stubs) happens
// in a subsequent step once HOF lambdas are fully supported in bundled Kotlin source.
//
// Each implementation delegates to the corresponding *To variant, which itself
// remains Swift-backed (kk_list_filter*To) until the accumulation HOF are also
// migrated (see MIGRATION-COL-002 / MIGRATION-COL-003 accumulation variants).

// ─── filter ──────────────────────────────────────────────────────────────────

/**
 * Returns a list containing only elements matching the given [predicate].
 *
 * @param predicate A function that returns `true` for elements to include.
 * @sample samples.collections.Collections.Filtering.filter
 */
public inline fun <T> Iterable<T>.filter(predicate: (T) -> Boolean): List<T> {
    return filterTo(mutableListOf(), predicate)
}

// ─── filterNot ───────────────────────────────────────────────────────────────

/**
 * Returns a list containing only elements not matching the given [predicate].
 *
 * @param predicate A function that returns `true` for elements to exclude.
 * @sample samples.collections.Collections.Filtering.filterNot
 */
public inline fun <T> Iterable<T>.filterNot(predicate: (T) -> Boolean): List<T> {
    return filterNotTo(mutableListOf(), predicate)
}

// ─── filterNotNull ───────────────────────────────────────────────────────────

/**
 * Returns a list containing all elements that are not `null`.
 *
 * @sample samples.collections.Collections.Filtering.filterNotNull
 */
public fun <T : Any> Iterable<T?>.filterNotNull(): List<T> {
    return filterNotNullTo(mutableListOf())
}

// ─── filterIndexed ───────────────────────────────────────────────────────────

/**
 * Returns a list containing only elements matching the given [predicate].
 *
 * @param predicate A function that takes the index of an element and the element itself
 *                  and returns `true` to include it in the result.
 * @sample samples.collections.Collections.Filtering.filterIndexed
 */
public inline fun <T> Iterable<T>.filterIndexed(predicate: (index: Int, T) -> Boolean): List<T> {
    return filterIndexedTo(mutableListOf(), predicate)
}

// ─── filterIsInstance ────────────────────────────────────────────────────────

/**
 * Returns a list containing all elements that are instances of specified type parameter [R].
 *
 * Requires `inline` and `reified` so that the element type is available at runtime
 * for the `is R` check performed inside [filterIsInstanceTo].
 *
 * @sample samples.collections.Collections.Filtering.filterIsInstance
 */
public inline fun <reified R> Iterable<*>.filterIsInstance(): List<R> {
    return filterIsInstanceTo(mutableListOf())
}
