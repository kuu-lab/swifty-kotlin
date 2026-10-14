import kotlin.coroutines.*
import kotlinx.coroutines.*
import kotlinx.coroutines.intrinsics.startCoroutineCancellable

@OptIn(InternalCoroutinesApi::class)
internal fun <R> (suspend () -> R).fireAndForget() {
    this.startCoroutineCancellable(NO_CALLBACK)
    this.startCoroutineCancellable<R>(NO_CALLBACK)
    this.startCoroutineCancellable(INITIALIZED_CALLBACK)
}

private val NO_CALLBACK = object : Continuation<Any?> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Any?>) = Unit
}

private val INITIALIZED_CALLBACK = object : Continuation<Any?> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Any?>) = Unit
}

fun main() {
    val block: suspend () -> String = { "completed" }
    block.fireAndForget()
    println("OK")
}
