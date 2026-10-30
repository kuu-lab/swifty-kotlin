import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking

class BufferOwner {
    fun buffer(capacity: Int): String = "owner=$capacity"
}

fun userFlowBuffer(): String {
    fun Flow<Int>.buffer(capacity: Int): String = "user-flow=$capacity"
    return flowOf(1).buffer(-3)
}

fun main() = runBlocking {
    val source = flowOf(1, 2)
    println("default=" + source.buffer().toList())
    println("zero=" + source.buffer(0).toList())
    println("two=" + source.buffer(2).toList())
    println("buffered=" + source.buffer(Channel.BUFFERED).toList())
    source.buffer(Channel.CONFLATED)
    println("conflated=accepted")
    source.buffer(0, BufferOverflow.DROP_LATEST)
    println("drop-latest=accepted")
    source.buffer(onBufferOverflow = BufferOverflow.DROP_OLDEST)
    println("default-overflow=accepted")
    try {
        source.buffer(-3)
        println("negative=accepted")
    } catch (e: IllegalArgumentException) {
        println("negative=rejected")
    }
    try {
        source.buffer(-3, BufferOverflow.DROP_LATEST)
        println("negative-overflow=accepted")
    } catch (e: IllegalArgumentException) {
        println("negative-overflow=rejected")
    }
    try {
        source.buffer(Channel.CONFLATED, BufferOverflow.DROP_OLDEST)
        println("conflated-overflow=accepted")
    } catch (e: IllegalArgumentException) {
        println("conflated-overflow=rejected")
    }
    println(BufferOwner().buffer(-3))
    println(userFlowBuffer())
}
