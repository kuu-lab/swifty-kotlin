import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.EmptyCoroutineContext

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
