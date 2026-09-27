import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted

private class Probe : Continuation<Int> {
    override val context = EmptyCoroutineContext
    override fun resumeWith(result: Result<Int>) {
        println(result.getOrThrow())
    }
}

fun main() {
    val created = Continuation<Int>(EmptyCoroutineContext) { result ->
        println(result.getOrThrow())
    }
    println(created.context === EmptyCoroutineContext)
    created.resumeWith(Result.success(7))
    val source: Continuation<Int> = Probe()
    println(source.context === EmptyCoroutineContext)
    source.resumeWith(Result.success(11))
    source.resume(12)
    try { source.resumeWithException(IllegalStateException("resume-exception")) } catch (e: IllegalStateException) { println(e.message) }
    checkThrownMembers()
    checkThrowingCompletion()
}

private class ThrowingProbe : Continuation<Int> {
    override val context: CoroutineContext
        get() = throw IllegalStateException("context-thrown")
    override fun resumeWith(result: Result<Int>) {
        throw IllegalStateException("resume-thrown")
    }
}

private fun checkThrownMembers() {
    val source: Continuation<Int> = ThrowingProbe()
    try { println(source.context) } catch (e: IllegalStateException) { println(e.message) }
    try { source.resumeWith(Result.success(1)) } catch (e: IllegalStateException) { println(e.message) }
    val callback = Continuation<Int>(EmptyCoroutineContext) { throw IllegalStateException("callback-thrown") }
    try { callback.resumeWith(Result.success(1)) } catch (e: IllegalStateException) { println(e.message) }
}

private suspend fun completedValue(): Int = 42

private fun checkThrowingCompletion() {
    val completion = Continuation<Int>(EmptyCoroutineContext) {
        throw IllegalStateException("completion-thrown")
    }
    val successful = (::completedValue).createCoroutineUnintercepted(completion)
    try { successful.resume(Unit) } catch (e: IllegalStateException) { println(e.message) }
    val failed = (::completedValue).createCoroutineUnintercepted(completion)
    try { failed.resumeWithException(IllegalStateException("input")) } catch (e: IllegalStateException) { println(e.message) }
}
