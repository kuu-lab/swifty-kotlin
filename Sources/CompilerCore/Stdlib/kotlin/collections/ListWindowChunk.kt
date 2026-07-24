package kotlin.collections

// MIGRATION-COL-009
// List window/chunk HOFs migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
// Functions: chunked, windowed, zipWithNext, zip

private external fun <T> __kk_list_chunked(receiver: Iterable<T>, size: Int): List<List<T>>
private external fun <T, R> __kk_list_chunked_transform(
    receiver: Iterable<T>,
    size: Int,
    transform: (List<T>) -> R
): List<R>
private external fun <T> __kk_list_windowed(
    receiver: Iterable<T>,
    size: Int,
    step: Int,
    partialWindows: Boolean
): List<List<T>>
private external fun <T, R> __kk_list_windowed_transform(
    receiver: Iterable<T>,
    size: Int,
    step: Int,
    partialWindows: Boolean,
    transform: (List<T>) -> R
): List<R>
private external fun <T, R> __kk_list_zip(
    receiver: Iterable<T>,
    other: Iterable<R>
): List<Pair<T, R>>
private external fun <T, R, V> __kk_list_zip_transform(
    receiver: Iterable<T>,
    other: Iterable<R>,
    transform: (T, R) -> V
): List<V>
private external fun <T> __kk_list_zipWithNext(receiver: Iterable<T>): List<Pair<T, T>>
private external fun <T, R> __kk_list_zipWithNextTransform(
    receiver: Iterable<T>,
    transform: (T, T) -> R
): List<R>

// ── chunked ──────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Iterable<T>.chunked(size: Int): List<List<T>>

public fun <T> Iterable<T>.chunked(size: Int): List<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    return __kk_list_chunked(this, size)
}

public fun <T, R> Iterable<T>.chunked(size: Int, transform: (List<T>) -> R): List<R> {
    require(size > 0) { "size must be positive, but was $size" }
    return __kk_list_chunked_transform(this, size, transform)
}

// ── windowed ─────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Iterable<T>.windowed(size, step, partialWindows): List<List<T>>

public fun <T> Iterable<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): List<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    return __kk_list_windowed(this, size, step, partialWindows)
}

public fun <T, R> Iterable<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (List<T>) -> R
): List<R> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    return __kk_list_windowed_transform(this, size, step, partialWindows, transform)
}

// ── zipWithNext ──────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T> Iterable<T>.zipWithNext(): List<Pair<T, T>>
//
// Uses an iterator pair (current/next) to avoid allocating an intermediate
// list.

public fun <T> Iterable<T>.zipWithNext(): List<Pair<T, T>> =
    __kk_list_zipWithNext(this)

public fun <T, R> Iterable<T>.zipWithNext(transform: (T, T) -> R): List<R> =
    __kk_list_zipWithNextTransform(this, transform)

// ── zip ──────────────────────────────────────────────────────────────────────
//
// Kotlin stdlib: fun <T, R> Iterable<T>.zip(other: Iterable<R>): List<Pair<T, R>>
//
// Result length equals the shorter of the two iterables, matching Kotlin
// stdlib and the Swift ABI implementation (min(lhs.count, rhs.count)).

public fun <T, R> Iterable<T>.zip(other: Iterable<R>): List<Pair<T, R>> =
    __kk_list_zip(this, other)

public fun <T, R, V> Iterable<T>.zip(other: Iterable<R>, transform: (T, R) -> V): List<V> =
    __kk_list_zip_transform(this, other, transform)
