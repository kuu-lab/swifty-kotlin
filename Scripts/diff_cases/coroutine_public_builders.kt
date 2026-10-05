import kotlin.coroutines.*

private class RecordingInterceptor : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> = ContinuationInterceptor.Key
    var calls = 0
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> {
        calls++
        return continuation
    }
}

private var pending: Continuation<Int>? = null
private suspend fun later(): Int = suspendCoroutine<Int> { pending = it }
private suspend fun immediate(): Int = suspendCoroutine<Int> { it.resume(42) }
private suspend fun failure(): Int = suspendCoroutine<Int> { it.resumeWithException(IllegalStateException("failure")) }

private fun throughParameter(block: suspend () -> Int, completion: Continuation<Int>) {
    block.startCoroutine(completion)
}
private fun returnedBlock(offset: Int): suspend () -> Int = { offset + 2 }
private suspend fun twice(): Int {
    val first = suspendCoroutine<Int> { pending = it }
    return first + suspendCoroutine<Int> { pending = it }
}
private suspend fun nullable(): String? = suspendCoroutine<String?> { it.resume(null) }

fun main() {
    val interceptor = RecordingInterceptor()
    val completion = Continuation<Int>(interceptor) { result ->
        println(if (result.isSuccess) "value:${result.getOrThrow()}" else "failed")
    }
    val block: suspend () -> Int = { 7 }
    block.startCoroutine(completion)
    val receiverBlock: suspend String.() -> Int = { length }
    receiverBlock.startCoroutine("abcd", completion)
    val created = block.createCoroutine(completion)
    println("created")
    created.resume(Unit)
    try {
        created.resume(Unit)
    } catch (e: IllegalStateException) {
        println("one-shot")
    }
    val receiverCreated = receiverBlock.createCoroutine("abc", completion)
    receiverCreated.resume(Unit)
    (::immediate).startCoroutine(completion)
    (::failure).startCoroutine(completion)
    (::later).startCoroutine(completion)
    println("suspended")
    pending!!.resume(99)
    try {
        pending!!.resume(100)
    } catch (e: IllegalStateException) {
        println("resume-once")
    }
    println("intercepts:${interceptor.calls}")
    throughParameter(returnedBlock(40), completion)
    val nullableCompletion = Continuation<String?>(EmptyCoroutineContext) { println(it.getOrThrow() == null) }
    (::nullable).startCoroutine(nullableCompletion)
    val safeBlock: (suspend () -> Int)? = ::immediate
    safeBlock?.startCoroutine(completion)
    (::twice).startCoroutine(completion)
    pending!!.resume(10)
    println("second-suspension")
    pending!!.resume(20)
}
