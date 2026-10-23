@file:Suppress("UNCHECKED_CAST")

package kotlin
class Result<out T> {
    val isSuccess: Boolean get() = true
    val isFailure: Boolean get() = false
    fun getOrThrow(): T = null!!
    fun exceptionOrNull(): Throwable? = null

    inline fun getOrNull(): T? = if (this.isFailure) null else this.getOrThrow()

    inline fun getOrDefault(defaultValue: @UnsafeVariance T): T =
        if (this.isFailure) defaultValue else this.getOrThrow()

    inline fun getOrElse(failureTransform: (Throwable) -> @UnsafeVariance T): T {
        val exception = this.exceptionOrNull()
        return if (exception == null) this.getOrThrow() else failureTransform(exception)
    }

    inline fun <R> map(transform: (T) -> R): Result<R> =
        if (this.isFailure) this as Result<R> else Result.success(transform(this.getOrThrow()))

    inline fun <R> mapCatching(transform: (T) -> R): Result<R> =
        if (this.isFailure) this as Result<R> else runCatching { transform(this.getOrThrow()) }

    inline fun <R> fold(onSuccess: (T) -> R, onFailure: (Throwable) -> R): R {
        val exception = this.exceptionOrNull()
        return if (exception == null) onSuccess(this.getOrThrow()) else onFailure(exception)
    }

    inline fun onSuccess(action: (T) -> Unit): Result<T> {
        if (this.isSuccess) action(this.getOrThrow())
        return this
    }

    inline fun onFailure(action: (Throwable) -> Unit): Result<T> {
        val exception = this.exceptionOrNull()
        if (exception != null) action(exception)
        return this
    }

    inline fun <R> recover(transform: (Throwable) -> R): Result<R> {
        val exception = this.exceptionOrNull()
        return if (exception == null) this as Result<R> else Result.success(transform(exception))
    }

    inline fun <R> recoverCatching(transform: (Throwable) -> R): Result<R> {
        val exception = this.exceptionOrNull()
        return if (exception == null) this as Result<R> else runCatching { transform(exception) }
    }

    companion object {
        fun <T> success(value: T): Result<T> = null!!
        fun <T> failure(exception: Throwable): Result<T> = null!!
    }
}

inline fun <R> runCatching(block: () -> R): Result<R> {
    return try {
        Result.success(block())
    } catch (exception: Throwable) {
        Result.failure(exception)
    }
}
