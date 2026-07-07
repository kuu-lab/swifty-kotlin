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

public class Result<T> private constructor() {
    public val isSuccess: Boolean
        get() = __kkRuntimeResultIsSuccess(this)

    public val isFailure: Boolean
        get() = __kkRuntimeResultIsFailure(this)

    public fun getOrNull(): T? =
        __kkRuntimeResultValueOrNull(this)

    public fun getOrDefault(defaultValue: T): T =
        if (resultIsSuccess(this)) getOrThrow() else defaultValue

    @KsSymbolName("kk_runtime_result_get_or_else")
    public external fun getOrElse(failureTransform: (Throwable) -> T): T

    public fun getOrThrow(): T =
        __kkRuntimeResultGetOrThrow(this)

    public fun exceptionOrNull(): Throwable? =
        __kkRuntimeResultExceptionOrNull(this)

    @KsSymbolName("kk_runtime_result_map")
    public external fun <R> map(transform: (T) -> R): Result<Any?>

    @KsSymbolName("kk_runtime_result_fold")
    public external fun <R> fold(successTransform: (T) -> R, failureTransform: (Throwable) -> R): R

    @KsSymbolName("kk_runtime_result_on_success")
    public external fun onSuccess(action: (T) -> Unit): Result<T>

    @KsSymbolName("kk_runtime_result_on_failure")
    public external fun onFailure(action: (Throwable) -> Unit): Result<T>

    @KsSymbolName("kk_runtime_result_recover")
    public external fun <R> recover(transform: (Throwable) -> R): Result<Any?>

    @KsSymbolName("kk_runtime_result_recover_catching")
    public external fun <R> recoverCatching(transform: (Throwable) -> R): Result<Any?>

}

@KsSymbolName("kk_runtime_result_run_catching")
public external fun <T> runCatching(block: () -> T): Result<T>
