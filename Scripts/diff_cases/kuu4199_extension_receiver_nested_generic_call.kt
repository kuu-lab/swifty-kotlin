// KUU-4199: a nested generic factory call used as an argument to an
// extension whose own type parameter is bound by a contravariant receiver
// position must receive the receiver-derived expected type, so its
// result-only type variable can be inferred (kotlinx-coroutines'
// `cont.resume(closed(closeCause))` in BufferedChannel).
class ChannelResult<out T> {
    companion object {
        fun <E> closed(cause: Throwable?): ChannelResult<E> = ChannelResult()
        fun <E> success(value: E): ChannelResult<E> = ChannelResult()
    }
}

interface CancellableContinuation<in T> {
    fun resume(value: T, onCancellation: ((cause: Throwable) -> Unit)?)
}

fun <T> CancellableContinuation<T>.resume(
    value: T,
    onCancellation: ((cause: Throwable) -> Unit)? = null
) {
    println("extension resume")
}

class Chan<E> {
    fun resumeClosed(cont: CancellableContinuation<ChannelResult<E>>, cause: Throwable?) {
        cont.resume(ChannelResult.closed(cause))
    }

    fun resumeSuccess(cont: CancellableContinuation<ChannelResult<E>>, element: E) {
        cont.resume(ChannelResult.success(element))
    }
}

fun main() {
    val cont = object : CancellableContinuation<ChannelResult<String>> {
        override fun resume(value: ChannelResult<String>, onCancellation: ((cause: Throwable) -> Unit)?) {
            println("member resume")
        }
    }
    Chan<String>().resumeClosed(cont, RuntimeException("closed"))
    Chan<String>().resumeSuccess(cont, "ok")
}
