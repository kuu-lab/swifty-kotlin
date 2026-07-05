package kotlin

public class Result<T> private constructor() {
    public val isSuccess: Boolean
        get() = __kk_result_isSuccess()

    public val isFailure: Boolean
        get() = __kk_result_isFailure()

    public fun getOrNull(): T? = __kk_result_getOrNull()

    public fun getOrDefault(defaultValue: T): T =
        __kk_result_getOrDefault(defaultValue)

    public fun getOrElse(failureTransform: (Throwable) -> T): T {
        return __kk_result_getOrElse(failureTransform)
    }

    public fun getOrThrow(): T = __kk_result_getOrThrow()

    public fun exceptionOrNull(): Throwable? = __kk_result_exceptionOrNull()

    public fun <R> map(transform: (T) -> R): Result<R> {
        return __kk_result_map(transform)
    }

    public fun <R> fold(successTransform: (T) -> R, failureTransform: (Throwable) -> R): R {
        return __kk_result_fold(successTransform, failureTransform)
    }

    public fun onSuccess(action: (T) -> Unit): Result<T> {
        return __kk_result_onSuccess(action)
    }

    public fun onFailure(action: (Throwable) -> Unit): Result<T> {
        return __kk_result_onFailure(action)
    }

    public fun <R> recover(transform: (Throwable) -> R): Result<R> {
        return __kk_result_recover(transform)
    }

    public fun <R> recoverCatching(transform: (Throwable) -> R): Result<R> {
        return __kk_result_recoverCatching(transform)
    }
}

public fun <T> runCatching(block: () -> T): Result<T> =
    __kk_runCatching(block)
