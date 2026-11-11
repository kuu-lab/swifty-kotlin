package kotlin.coroutines

interface Continuation<in T> {
    val context: CoroutineContext
    fun resumeWith(result: kotlin.Result<T>)
}
fun <T> Continuation<T>.resume(value: T) {}
fun <T> Continuation<T>.resumeWithException(exception: Throwable) {}
suspend fun <T> suspendCoroutine(block: (Continuation<T>) -> Unit): T = null!!
fun <T> (suspend () -> T).startCoroutine(completion: Continuation<T>) {}
fun <R, T> (suspend R.() -> T).startCoroutine(receiver: R, completion: Continuation<T>) {}
fun <T> (suspend () -> T).createCoroutine(completion: Continuation<T>): Continuation<Unit> = null!!
fun <R, T> (suspend R.() -> T).createCoroutine(receiver: R, completion: Continuation<T>): Continuation<Unit> = null!!
