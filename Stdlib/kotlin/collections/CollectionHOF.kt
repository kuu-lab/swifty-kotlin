package kotlin.collections

// MIGRATION-COL-002
// List transform HOF functions: map, mapIndexed, mapNotNull, flatMap, flatten.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//   kk_list_map, kk_list_mapIndexed, kk_list_mapNotNull, kk_list_flatMap, kk_list_flatten
//
// NOTE: Not yet wired into the compiler pipeline.
// CollectionLiteralLoweringPass still intercepts all HOF call sites and
// rewrites them to kk_* ABI calls. This file is the migration target; wiring
// (and removal of the corresponding entries in CollectionLiteralLoweringPass+LookupTables.swift
// and CollectionLiteralLoweringPass+CallRewriteHOFCore.swift) happens in a follow-up task.

/**
 * Returns a list containing the results of applying the given [transform] function
 * to each element in the original collection.
 */
public fun <T, R> Iterable<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        result.add(transform(element))
    }
    return result
}

/**
 * Returns a list containing the results of applying the given [transform] function
 * to each element and its index in the original collection.
 *
 * @param transform function that takes the index of an element and the element itself
 * and returns the result of the transform applied to the element.
 */
public fun <T, R> Iterable<T>.mapIndexed(transform: (index: Int, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

/**
 * Returns a list containing only the non-null results of applying the given [transform] function
 * to each element in the original collection.
 */
public fun <T, R : Any> Iterable<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val r = transform(element)
        if (r != null) result.add(r)
    }
    return result
}

/**
 * Returns a single list of all elements yielded from results of [transform] function being invoked
 * on each element of the original collection.
 */
public fun <T, R> Iterable<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val sub = transform(element)
        for (subElement in sub) {
            result.add(subElement)
        }
    }
    return result
}

/**
 * Returns a single list of all elements from all collections in the given collection.
 */
public fun <T> Iterable<Iterable<T>>.flatten(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        for (subElement in element) {
            result.add(subElement)
        }
    }
    return result
}
