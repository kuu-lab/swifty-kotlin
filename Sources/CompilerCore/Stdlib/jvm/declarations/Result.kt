package kotlin
class Result<out T> {
    val isSuccess: Boolean get() = true
    val isFailure: Boolean get() = false
    fun getOrThrow(): T = null!!
    fun exceptionOrNull(): Throwable? = null
}