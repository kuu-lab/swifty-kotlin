package kotlin.coroutines
interface CoroutineContext
object EmptyCoroutineContext: CoroutineContext {
    override fun toString(): String = "EmptyCoroutineContext"
}
interface Continuation<in T> {
    val context: CoroutineContext
    fun resumeWith(result: kotlin.Result<T>)
}
