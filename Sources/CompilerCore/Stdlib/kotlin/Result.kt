package kotlin

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_runtime_result_run_catching")
@PublishedApi
internal external fun <T> __kkRuntimeResultRunCatching(block: () -> T): Result<T>

public inline fun <T> runCatching(block: () -> T): Result<T> {
    return try {
        Result.success(block())
    } catch (exception: Throwable) {
        Result.failure(exception)
    }
}
