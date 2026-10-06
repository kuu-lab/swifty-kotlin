// NOTE: Requires kotlinx-coroutines on classpath.
// KUU-971: terminal channel exceptions accept nullable messages.
import kotlinx.coroutines.channels.ClosedSendChannelException
import kotlinx.coroutines.channels.ClosedReceiveChannelException

fun main() {
    val send: IllegalStateException = ClosedSendChannelException("send closed")
    val receive: NoSuchElementException = ClosedReceiveChannelException("receive closed")
    println(send.message)
    println(receive.message)
    println(send.cause == null)
    println(receive.cause == null)

    val message: String? = null
    val nullSend: IllegalStateException = ClosedSendChannelException(message)
    val nullReceive: NoSuchElementException = ClosedReceiveChannelException(null)
    println(nullSend.message == null)
    println(nullReceive.message == null)
    println(nullSend.cause == null)
    println(nullReceive.cause == null)
}
