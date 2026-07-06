package kotlin

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_runtime_result_success")
private external fun __kkRuntimeResultSuccess(value: Any?): Result<Any?>

@KsSymbolName("kk_runtime_result_failure")
private external fun __kkRuntimeResultFailure(exception: Throwable): Result<Any?>

@KsSymbolName("kk_runtime_result_is_success")
private external fun __kkRuntimeResultIsSuccess(result: Any?): Boolean

@KsSymbolName("kk_runtime_result_value_or_null")
private external fun __kkRuntimeResultValueOrNull(result: Any?): Any?

@KsSymbolName("kk_runtime_result_exception_or_null")
private external fun __kkRuntimeResultExceptionOrNull(result: Any?): Throwable?

private fun resultSuccess(value: Any?): Result<Any?> =
    __kkRuntimeResultSuccess(value)

private fun resultFailure(exception: Throwable): Result<Any?> =
    __kkRuntimeResultFailure(exception)

private fun <T> Result<T>.failureException(): Throwable {
    val exception = exceptionOrNull()
    if (exception != null) return exception
    return RuntimeException("Result failure without exception")
}

public class Result<T> private constructor() {
    public val isSuccess: Boolean
        get() = __kkRuntimeResultIsSuccess(this)

    public val isFailure: Boolean
        get() = !isSuccess

    public fun getOrNull(): T? =
        __kkRuntimeResultValueOrNull(this) as T?

    public fun getOrDefault(defaultValue: T): T =
        if (isSuccess) getOrThrow() else defaultValue

    public fun getOrElse(failureTransform: (Throwable) -> T): T {
        if (isSuccess) return getOrThrow()
        return failureTransform(failureException())
    }

    @Suppress("UNCHECKED_CAST")
    public fun getOrThrow(): T {
        val exception = exceptionOrNull()
        if (exception != null) throw exception
        return getOrNull() as T
    }

    public fun exceptionOrNull(): Throwable? =
        __kkRuntimeResultExceptionOrNull(this)

    public fun <R> map(transform: (T) -> R): Result<Any?> {
        if (isFailure) return resultFailure(failureException())
        return resultSuccess(transform(getOrThrow()))
    }

    public fun <R> fold(successTransform: (T) -> R, failureTransform: (Throwable) -> R): R {
        if (isSuccess) return successTransform(getOrThrow())
        return failureTransform(failureException())
    }

    public fun onSuccess(action: (T) -> Unit): Result<T> {
        if (isSuccess) action(getOrThrow())
        return this
    }

    public fun onFailure(action: (Throwable) -> Unit): Result<T> {
        if (isFailure) action(failureException())
        return this
    }

    public fun <R> recover(transform: (Throwable) -> R): Result<Any?> {
        if (isSuccess) return resultSuccess(getOrThrow())
        return resultSuccess(transform(failureException()))
    }

    public fun <R> recoverCatching(transform: (Throwable) -> R): Result<Any?> {
        if (isSuccess) return resultSuccess(getOrThrow())
        return try {
            resultSuccess(transform(failureException()))
        } catch (exception: Throwable) {
            resultFailure(exception)
        }
    }

    public fun component1(): T? =
        getOrNull()

    public fun component2(): Throwable? =
        exceptionOrNull()
}

public fun <T> runCatching(block: () -> T): Result<T> {
    return try {
        resultSuccess(block())
            as Result<T>
    } catch (exception: Throwable) {
        resultFailure(exception)
            as Result<T>
    }
}
