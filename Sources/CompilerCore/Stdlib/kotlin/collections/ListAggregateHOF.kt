package kotlin.collections

// MIGRATION-COL-004
// List aggregate HOFs migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//   kk_list_fold, kk_list_foldRight, kk_list_reduce, kk_list_reduceOrNull,
//   kk_list_scan, kk_list_runningFold
//
// NOTE: Bundled source is injected via BundledKotlinStdlib.kotlinCollectionsSource.
// Sema binds these definitions through bindBundledListAggregateSource in
// CallTypeChecker+MemberCallInferenceCollectionFlow.swift.
// CollectionLiteralLoweringPass preserves source-backed calls in shouldPreserveSourceBackedAggregateCall.

public inline fun <T, R> List<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    var i = 0
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        i += 1
    }
    return accumulator
}

public inline fun <T, R> List<T>.foldRight(initial: R, operation: (T, R) -> R): R {
    var accumulator = initial
    var i = size - 1
    while (i >= 0) {
        accumulator = operation(this[i], accumulator)
        i -= 1
    }
    return accumulator
}

public inline fun <T> List<T>.reduce(operation: (T, T) -> T): T {
    if (size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = this[0]
    var i = 1
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        i += 1
    }
    return accumulator
}

public inline fun <T> List<T>.reduceOrNull(operation: (T, T) -> T): T? {
    if (size == 0) return null
    var accumulator = this[0]
    var i = 1
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        i += 1
    }
    return accumulator
}

public inline fun <T, R> List<T>.scan(initial: R, operation: (R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}

public inline fun <T, R> List<T>.runningFold(initial: R, operation: (R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}
