package kotlin
@kotlin.jvm.JvmInline
value class Result<out T>(val value: Any?) {
    val isSuccess: Boolean get() = !(value is Failure)
    val isFailure: Boolean get() = value is Failure
    fun getOrThrow(): T { kotlin.throwOnFailure(value); return value as T }
    fun getOrNull(): T? = if (value is Failure) null else value as T?
    fun exceptionOrNull(): Throwable? = if (value is Failure) value.exception else null
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
