// KUU-4193: an inferred getter-only property whose body is an `as` cast must
// publish its type before an earlier-checked declaration reads it.
// `closeCause` mirrors kotlinx.coroutines BufferedChannel: a protected
// `val closeCause get() = box as Throwable?` read by `s.close(closeCause)`
// in the subclass declared before the base class (upstream file order puts
// BroadcastChannel.kt ahead of BufferedChannel.kt). The `Any?` header
// placeholder used to reach overload resolution and reject the call with
// KSWIFTK-SEMA-0473.
interface SendChannel<E> {
    fun close(cause: Throwable? = null): Boolean
}

class BroadcastChannelImpl<E> : BufferedChannel<E>() {
    fun openSubscription(): BufferedChannel<E> {
        val s = SubscriberBuffered<E>()
        if (closeCause != null) {
            s.close(closeCause)
            return s
        }
        return s
    }
}

class SubscriberBuffered<E> : BufferedChannel<E>()

open class BufferedChannel<E> : SendChannel<E> {
    private val box: Any? = Throwable("closed")
    protected val closeCause get() = box as Throwable?
    override fun close(cause: Throwable?): Boolean = cause != null
}

fun main() {
    println(BroadcastChannelImpl<Int>().openSubscription() != null)
}
