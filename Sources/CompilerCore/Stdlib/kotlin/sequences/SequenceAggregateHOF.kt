package kotlin.collections

// MIGRATION-SEQ-004
// Sequence aggregate HOFs migrated to Kotlin source.
// Placed in kotlin.collections package for Map/MutableMap/List/MutableList resolution.
// Uses "for in" iteration to avoid polluting toList() overload resolution
// (this.toList() in kotlin.collections would make Collection.toList() resolve to
// kk_sequence_to_list instead of kk_collection_toList in Sema dispatch).
//
// Migrated: fold, reduce, scan, sumOf, maxByOrNull, minByOrNull
// Deferred (MIGRATION-SEQ-004b): associate, associateBy, groupBy
//   — MutableMap→Map return-type coercion not yet handled by kswiftc Sema.

public fun <T, R> Sequence<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    for (elem in this) {
        accumulator = operation(accumulator, elem)
    }
    return accumulator
}

public fun <T> Sequence<T>.reduce(operation: (T, T) -> T): T {
    var accumulator: T? = null
    var first = true
    for (elem in this) {
        if (first) { accumulator = elem; first = false }
        else { accumulator = operation(accumulator!!, elem) }
    }
    if (first) throw UnsupportedOperationException("Empty sequence can't be reduced.")
    return accumulator!!
}

public fun <T, R> Sequence<T>.scan(initial: R, operation: (R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    for (elem in this) {
        accumulator = operation(accumulator, elem)
        result.add(accumulator)
    }
    return result
}

public fun <T> Sequence<T>.sumOf(selector: (T) -> Int): Int {
    var sum = 0
    for (elem in this) { sum += selector(elem) }
    return sum
}

public fun <T, R : Comparable<R>> Sequence<T>.maxByOrNull(selector: (T) -> R): T? {
    var bestElem: T? = null
    var bestKey: R? = null
    for (elem in this) {
        val key = selector(elem)
        if (bestKey == null || key > bestKey!!) { bestElem = elem; bestKey = key }
    }
    return bestElem
}

public fun <T, R : Comparable<R>> Sequence<T>.minByOrNull(selector: (T) -> R): T? {
    var bestElem: T? = null
    var bestKey: R? = null
    for (elem in this) {
        val key = selector(elem)
        if (bestKey == null || key < bestKey!!) { bestElem = elem; bestKey = key }
    }
    return bestElem
}
