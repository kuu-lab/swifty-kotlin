@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED

fun main() {
    val completion = Continuation<Int>(EmptyCoroutineContext) { println(it.getOrThrow()) }
    println(SafeContinuation(completion, 42).getOrThrow())
    println(SafeContinuation(completion, null).getOrThrow())
    val immediate = SafeContinuation(completion)
    println(immediate.context === EmptyCoroutineContext)
    immediate.resumeWith(Result.success(42))
    println(immediate.getOrThrow())
    try { immediate.resumeWith(Result.success(43)) } catch (e: IllegalStateException) { println(e.message) }

    val suspended = SafeContinuation(completion)
    println(suspended.getOrThrow() === COROUTINE_SUSPENDED)
    suspended.resumeWith(Result.success(9))
    println(suspended.getOrThrow() === COROUTINE_SUSPENDED)
    try { suspended.resumeWith(Result.success(10)) } catch (e: IllegalStateException) { println(e.message) }

    val failed = SafeContinuation(completion)
    failed.resumeWith(Result.failure<Int>(IllegalStateException("failed-before-suspension")))
    try { println(failed.getOrThrow()) } catch (e: IllegalStateException) { println(e.message) }

    val nullable = SafeContinuation(Continuation<String?>(EmptyCoroutineContext) { println("unexpected") })
    nullable.resumeWith(Result.success(null))
    println(nullable.getOrThrow())
}
