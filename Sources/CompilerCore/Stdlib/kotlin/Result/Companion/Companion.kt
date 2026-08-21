package kotlin

/** Returns a successful [Result] containing [value]. */
public inline fun <T> Result.Companion.success(value: T): Result<T> =
    runCatching<T> { value }

/** Returns a failed [Result] containing [exception]. */
public inline fun <T> Result.Companion.failure(exception: Throwable): Result<T> =
    runCatching<T> { throw exception }
