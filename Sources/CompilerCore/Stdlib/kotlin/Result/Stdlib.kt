@file:Suppress("UNCHECKED_CAST")

package kotlin

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_runtime_result_is_success")
private external fun __kkRuntimeResultIsSuccess(result: Any?): Boolean

@KsSymbolName("kk_runtime_result_is_failure")
private external fun __kkRuntimeResultIsFailure(result: Any?): Boolean

@KsSymbolName("kk_runtime_result_value_or_null")
private external fun <T> __kkRuntimeResultValueOrNull(result: Result<T>): T?

@KsSymbolName("kk_runtime_result_exception_or_null")
private external fun __kkRuntimeResultExceptionOrNull(result: Any?): Throwable?

@KsSymbolName("kk_runtime_result_get_or_throw")
private external fun <T> __kkRuntimeResultGetOrThrow(result: Result<T>): T

private fun <T> resultIsSuccess(result: Result<T>): Boolean =
    __kkRuntimeResultIsSuccess(result)

// The runtime stores Result values in RuntimeResultBox instances. Keep the
// constructor internal, matching Kotlin's @PublishedApi internal
// constructor, and lower its calls to the runtime success factory.
public class Result<out T> {
    @KsSymbolName("kk_runtime_result_success")
    @PublishedApi
    internal constructor(value: Any?)

    public val isSuccess: Boolean
        get() = __kkRuntimeResultIsSuccess(this)

    public val isFailure: Boolean
        get() = __kkRuntimeResultIsFailure(this)

    public fun getOrNull(): T? =
        __kkRuntimeResultValueOrNull(this)

    public fun getOrDefault(defaultValue: @UnsafeVariance T): T =
        if (resultIsSuccess(this)) getOrThrow() else defaultValue

    public inline fun getOrElse(failureTransform: (Throwable) -> @UnsafeVariance T): T {
        val exception = exceptionOrNull()
        return if (exception == null) getOrThrow() else failureTransform(exception)
    }

    public fun getOrThrow(): T =
        __kkRuntimeResultGetOrThrow(this)

    public fun exceptionOrNull(): Throwable? =
        __kkRuntimeResultExceptionOrNull(this)

    public inline fun <R> map(transform: (T) -> R): Result<R> =
        if (isSuccess) Result.success(transform(getOrThrow())) else this as Result<R>

    public inline fun <R> mapCatching(transform: (T) -> R): Result<R> =
        if (isSuccess) runCatching { transform(getOrThrow()) } else this as Result<R>

    public inline fun <R> fold(successTransform: (T) -> R, failureTransform: (Throwable) -> R): R {
        val exception = exceptionOrNull()
        return if (exception == null) successTransform(getOrThrow()) else failureTransform(exception)
    }

    public inline fun onSuccess(action: (T) -> Unit): Result<T> {
        if (isSuccess) action(getOrThrow())
        return this
    }

    public inline fun onFailure(action: (Throwable) -> Unit): Result<T> {
        val exception = exceptionOrNull()
        if (exception != null) action(exception)
        return this
    }

    public inline fun <R> recover(transform: (Throwable) -> R): Result<R> {
        val exception = exceptionOrNull()
        return if (exception == null) this as Result<R> else Result.success(transform(exception))
    }

    public inline fun <R> recoverCatching(transform: (Throwable) -> R): Result<R> {
        val exception = exceptionOrNull()
        return if (exception == null) this as Result<R> else runCatching { transform(exception) }
    }

    public companion object {}
}

/** Returns a successful [Result] containing [value]. */
public inline fun <T> Result.Companion.success(value: T): Result<T> =
    Result<T>(value)

/** Returns a failed [Result] containing [exception]. */
public inline fun <T> Result.Companion.failure(exception: Throwable): Result<T> =
    __kkRuntimeResultRunCatching<T> { throw exception }
