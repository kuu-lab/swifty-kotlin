package kotlin.collections

// MIGRATION-ITER-001
// Iterable aggregate HOFs that return List<R> so an Iterable-typed receiver
// (e.g. `val xs: Iterable<Int> = setOf(...)`) does not accidentally dispatch to
// Sequence<T>.scan/scanIndexed/runningFold/runningFoldIndexed, which return
// Sequence<R> and therefore print as an object handle.
//
// Sequence receivers continue to use the Sequence variants in
// SequenceAggregateHOF.kt, which return Sequence<R>.

public inline fun <T, R> Iterable<T>.scan(initial: R, operation: (acc: R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    for (element in this) {
        accumulator = operation(accumulator, element)
        result.add(accumulator)
    }
    return result
}

public inline fun <T, R> Iterable<T>.scanIndexed(initial: R, operation: (Int, acc: R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    var index = 0
    result.add(accumulator)
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        result.add(accumulator)
        index += 1
    }
    return result
}

public inline fun <T, R> Iterable<T>.runningFold(initial: R, operation: (acc: R, T) -> R): List<R> =
    scan(initial, operation)

public inline fun <T, R> Iterable<T>.runningFoldIndexed(initial: R, operation: (Int, acc: R, T) -> R): List<R> =
    scanIndexed(initial, operation)

public inline fun <S, T : S> Iterable<T>.runningReduce(operation: (acc: S, T) -> S): List<S> {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return emptyList()
    var accumulator: S = iterator.next()
    val result = mutableListOf<S>()
    result.add(accumulator)
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
        result.add(accumulator)
    }
    return result
}

public inline fun <S, T : S> Iterable<T>.runningReduceIndexed(operation: (index: Int, acc: S, T) -> S): List<S> {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return emptyList()
    var accumulator: S = iterator.next()
    val result = mutableListOf<S>()
    result.add(accumulator)
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        result.add(accumulator)
        index += 1
    }
    return result
}
