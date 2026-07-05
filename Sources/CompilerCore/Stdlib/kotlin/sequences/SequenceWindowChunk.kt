package kotlin.sequences

// MIGRATION-SEQ-005
// Sequence window/limiting HOFs migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSequence.swift
// Functions: take, takeWhile, drop, dropWhile, chunked, windowed,
//            zip, zipWithNext, distinct, distinctBy
//
// Runtime-backed bridge members named __kk_sequence_* remain synthetic while
// sequence handle operations are still implemented by RuntimeSequence.swift.

public fun <T> Sequence<T>.take(n: Int): Sequence<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    return this.__kk_sequence_take(n)
}

public fun <T> Sequence<T>.takeWhile(predicate: (T) -> Boolean): Sequence<T> =
    this.__kk_sequence_takeWhile(predicate)

public fun <T> Sequence<T>.drop(n: Int): Sequence<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    return this.__kk_sequence_drop(n)
}

public fun <T> Sequence<T>.dropWhile(predicate: (T) -> Boolean): Sequence<T> =
    this.__kk_sequence_dropWhile(predicate)

public fun <T> Sequence<T>.chunked(size: Int): Sequence<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    return this.__kk_sequence_chunked(size)
}

public fun <T, R> Sequence<T>.chunked(size: Int, transform: (List<T>) -> R): Sequence<R> {
    require(size > 0) { "size must be positive, but was $size" }
    return this.__kk_sequence_chunked_transform(size, transform)
}

public fun <T> Sequence<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): Sequence<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    return this.__kk_sequence_windowed(size, step, partialWindows)
}

public fun <T, R> Sequence<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (List<T>) -> R
): Sequence<R> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    return this.__kk_sequence_windowed_transform(size, step, partialWindows, transform)
}

public fun <T, R> Sequence<T>.zip(other: Sequence<R>): Sequence<Pair<T, R>> =
    this.__kk_sequence_zip(other)

public fun <T, R, V> Sequence<T>.zip(other: Sequence<R>, transform: (T, R) -> V): Sequence<V> =
    this.__kk_sequence_zip_transform(other, transform)

public fun <T> Sequence<T>.zipWithNext(): Sequence<Pair<T, T>> =
    this.__kk_sequence_zipWithNext()

public fun <T, R> Sequence<T>.zipWithNext(transform: (T, T) -> R): Sequence<R> =
    this.__kk_sequence_zipWithNextTransform(transform)

public fun <T> Sequence<T>.distinct(): Sequence<T> =
    this.__kk_sequence_distinct()

public fun <T, K> Sequence<T>.distinctBy(selector: (T) -> K): Sequence<T> =
    this.__kk_sequence_distinctBy(selector)
