@file:kotlin.jvm.JvmName("ResultKt")
package kotlin
fun createFailure(exception: Throwable): Any = Result.Failure(exception)
fun throwOnFailure(value: Any?) { if (value is Result.Failure) throw value.exception }
inline fun <R> runCatching(block: () -> R): Result<R> =
    try { Result.success(block()) } catch (exception: Throwable) { Result.failure(exception) }
