package kotlin.collections

// MIGRATION-COL-004
// List aggregate HOFs migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//   kk_list_fold, kk_list_foldRight, kk_list_reduce, kk_list_reduceOrNull,
//   kk_list_scan, kk_list_runningFold

public inline fun <T, R> List<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    var i = 0
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        i += 1
    }
    return accumulator
}

public inline fun <T, R> List<T>.foldIndexed(initial: R, operation: (Int, R, T) -> R): R {
    var accumulator = initial
    var i = 0
    while (i < size) {
        accumulator = operation(i, accumulator, this[i])
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

public inline fun <T, R> List<T>.foldRightIndexed(initial: R, operation: (Int, T, R) -> R): R {
    var accumulator = initial
    var i = size - 1
    while (i >= 0) {
        accumulator = operation(i, this[i], accumulator)
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

public inline fun <T> List<T>.reduceIndexed(operation: (Int, T, T) -> T): T {
    if (size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = this[0]
    var i = 1
    while (i < size) {
        accumulator = operation(i - 1, accumulator, this[i])
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

public inline fun <T> List<T>.reduceIndexedOrNull(operation: (Int, T, T) -> T): T? {
    if (size == 0) return null
    var accumulator = this[0]
    var i = 1
    while (i < size) {
        accumulator = operation(i - 1, accumulator, this[i])
        i += 1
    }
    return accumulator
}

public inline fun <T> List<T>.reduceRight(operation: (T, T) -> T): T {
    if (size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = this[size - 1]
    var i = size - 2
    while (i >= 0) {
        accumulator = operation(this[i], accumulator)
        i -= 1
    }
    return accumulator
}

public inline fun <T> List<T>.reduceRightIndexed(operation: (Int, T, T) -> T): T {
    if (size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = this[size - 1]
    var i = size - 2
    while (i >= 0) {
        accumulator = operation(i, this[i], accumulator)
        i -= 1
    }
    return accumulator
}

public inline fun <T> List<T>.reduceRightOrNull(operation: (T, T) -> T): T? {
    if (size == 0) return null
    var accumulator = this[size - 1]
    var i = size - 2
    while (i >= 0) {
        accumulator = operation(this[i], accumulator)
        i -= 1
    }
    return accumulator
}

public inline fun <T> List<T>.reduceRightIndexedOrNull(operation: (Int, T, T) -> T): T? {
    if (size == 0) return null
    var accumulator = this[size - 1]
    var i = size - 2
    while (i >= 0) {
        accumulator = operation(i, this[i], accumulator)
        i -= 1
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

public inline fun <T, R> List<T>.scanIndexed(initial: R, operation: (Int, R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < size) {
        accumulator = operation(i, accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}

public inline fun <T, R> List<T>.scanReduce(operation: (T, T) -> T): List<T> {
    if (size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    val result = mutableListOf<T>()
    var accumulator = this[0]
    result.add(accumulator)
    var i = 1
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

public inline fun <T, R> List<T>.runningFoldIndexed(initial: R, operation: (Int, R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < size) {
        accumulator = operation(i, accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}

public inline fun <T> List<T>.runningReduce(operation: (T, T) -> T): List<T> {
    if (size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    val result = mutableListOf<T>()
    var accumulator = this[0]
    result.add(accumulator)
    var i = 1
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}

public inline fun <T> List<T>.runningReduceIndexed(operation: (Int, T, T) -> T): List<T> {
    if (size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    val result = mutableListOf<T>()
    var accumulator = this[0]
    result.add(accumulator)
    var i = 1
    while (i < size) {
        accumulator = operation(i - 1, accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}
