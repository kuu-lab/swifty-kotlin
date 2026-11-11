// KUU-4202: BufferedChannel.kt:2182, reduced from kotlinx.coroutines
// 7e0d1b3e9ca83652427ae00dda7d1673f058a743. Keep the upstream API shape
// local: bundled CancellableContinuation.resume has an extra default argument,
// which would hide the Continuation.resume extension inference path.
package waiter

import waiter.ChannelResult.Companion.closed

interface Waiter

interface Continuation<in T> {
    fun resumeWith(value: T)
}

fun <T> Continuation<T>.resume(value: T) = resumeWith(value)

interface CancellableContinuation<in T> : Continuation<T> {
    fun resume(value: T, onCancellation: ((Throwable) -> Unit)?)
}

class CancellableContinuationImpl<in T>(val label: String) : CancellableContinuation<T>, Waiter {
    override fun resumeWith(value: T) {
        println(label)
    }

    override fun resume(value: T, onCancellation: ((Throwable) -> Unit)?) {
        println("member overload")
    }
}

class ChannelResult<out T> {
    companion object {
        fun <E> closed(cause: Throwable?): ChannelResult<E> = ChannelResult()
    }
}

class ReceiveCatching<E>(val cont: CancellableContinuationImpl<ChannelResult<E>>) : Waiter by cont

class BufferedChannel<E>(val closeCause: Throwable?) {
    private fun Waiter.resumeWaiterOnClosedChannel() {
        when (this) {
            is ReceiveCatching<*> -> cont.resume(closed(closeCause))
            else -> println("other waiter")
        }
    }

    fun close(waiter: Waiter) = waiter.resumeWaiterOnClosedChannel()
}

fun main() {
    val channel = BufferedChannel<Any?>(null)
    channel.close(ReceiveCatching(CancellableContinuationImpl<ChannelResult<String>>("string closed")))
    channel.close(ReceiveCatching(CancellableContinuationImpl<ChannelResult<Int>>("int closed")))
    channel.close(CancellableContinuationImpl<Any?>("unused"))
}
