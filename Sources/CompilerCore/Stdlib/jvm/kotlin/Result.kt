@file:Suppress("UNCHECKED_CAST")

package kotlin
@kotlin.jvm.JvmInline
value class Result<out T>(val value: Any?) {
    val isSuccess: Boolean get() = !(value is Failure)
    val isFailure: Boolean get() = value is Failure
    fun getOrThrow(): T { kotlin.throwOnFailure(value); return value as T }
    fun getOrNull(): T? = if (value is Failure) null else value as T?
    fun getOrDefault(defaultValue: @UnsafeVariance T): T = if (isSuccess) getOrThrow() else defaultValue
    inline fun getOrElse(failureTransform: (Throwable) -> @UnsafeVariance T): T {
        val exception = exceptionOrNull()
        return if (exception == null) getOrThrow() else failureTransform(exception)
    }
    fun exceptionOrNull(): Throwable? = if (value is Failure) value.exception else null
    inline fun <R> map(transform: (T) -> R): Result<R> =
        if (isSuccess) Result.success(transform(getOrThrow())) else this as Result<R>
    inline fun <R> mapCatching(transform: (T) -> R): Result<R> =
        if (isSuccess) runCatching { transform(getOrThrow()) } else this as Result<R>
    inline fun <R> fold(onSuccess: (T) -> R, onFailure: (Throwable) -> R): R {
        val exception = exceptionOrNull()
        return if (exception == null) onSuccess(getOrThrow()) else onFailure(exception)
    }
    inline fun onSuccess(action: (T) -> Unit): Result<T> {
        if (isSuccess) action(getOrThrow())
        return this
    }
    inline fun onFailure(action: (Throwable) -> Unit): Result<T> {
        val exception = exceptionOrNull()
        if (exception != null) action(exception)
        return this
    }
    inline fun <R> recover(transform: (Throwable) -> R): Result<R> {
        val exception = exceptionOrNull()
        return if (exception == null) this as Result<R> else Result.success(transform(exception))
    }
    inline fun <R> recoverCatching(transform: (Throwable) -> R): Result<R> {
        val exception = exceptionOrNull()
        return if (exception == null) this as Result<R> else runCatching { transform(exception) }
    }
    override fun toString(): String = if (value is Failure) value.toString() else "Success($value)"
    companion object {
        fun <T> success(value: T): Result<T> = Result<T>(value)
        fun <T> failure(exception: Throwable): Result<T> = Result<T>(Failure(exception))
    }
    class Failure(value: Throwable) {
        @kotlin.jvm.JvmField val exception: Throwable = value
        override fun equals(other: Any?): Boolean = other is Failure && exception == other.exception
        override fun hashCode(): Int = exception.hashCode()
        override fun toString(): String = "Failure($exception)"
    }
}
