package kotlin.coroutines

interface Continuation<in T> {
    val context: CoroutineContext
    fun resumeWith(result: kotlin.Result<T>)
}
