import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted

// KUU-1597 Sema owner: pin Continuation construction, context, resume extensions, and suspend-function continuation typing; callback/exception behavior stays in Scripts/diff_cases/stdlib_kotlin_coroutines_Continuation_Continuation_n.kt.
private class Probe : Continuation<Int> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Int>) {}
}

private class ThrowingProbe : Continuation<Int> {
    override val context: CoroutineContext
        get() = throw IllegalStateException("context-thrown")
    override fun resumeWith(result: Result<Int>) {
        throw IllegalStateException("resume-thrown")
    }
}

private suspend fun completedValue(): Int = 42

fun main() {
    val created: Continuation<Int> = Continuation<Int>(EmptyCoroutineContext) {}
    val createdContext: CoroutineContext = created.context
    created.resumeWith(Result.success(7))

    val source: Continuation<Int> = Probe()
    val sourceContext: CoroutineContext = source.context
    source.resumeWith(Result.success(11))
    source.resume(12)
    source.resumeWithException(IllegalStateException("resume-exception"))

    val throwing: Continuation<Int> = ThrowingProbe()
    val throwingContext: CoroutineContext = throwing.context

    val completion: Continuation<Int> = Continuation<Int>(EmptyCoroutineContext) {}
    val successful: Continuation<Unit> = (::completedValue).createCoroutineUnintercepted(completion)
    val failed: Continuation<Unit> = (::completedValue).createCoroutineUnintercepted(completion)
}
