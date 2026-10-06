import kotlin.coroutines.*

// KUU-1236: local extensions on interface receivers, including suspend calls
// and indexed properties accessed through the implicit extension receiver.
interface Src {
    val size: Long
    val buffer: ByteArray
}

class Data(override val size: Long, override val buffer: ByteArray) : Src

suspend fun outer(s: Src) {
    fun Src.helper(): Long = size
    suspend fun Src.suspHelper(): Boolean = size > 0
    suspend fun Src.bufferHelper(): Byte {
        fun read(): Byte = buffer[1]
        return read()
    }
    println(s.helper())
    println(s.suspHelper())
    println(s.bufferHelper())
}

fun topLevel(s: Src) {
    fun Src.helper2(): Long = size
    fun Src.bufferRegular(): Byte {
        fun read(): Byte = buffer[1]
        return read()
    }
    println(s.helper2())
    println(s.bufferRegular())
}

fun main() {
    val present: Src = Data(3L, byteArrayOf(10, 20))
    val empty: Src = Data(0L, byteArrayOf(30, 40))
    topLevel(present)
    topLevel(empty)
    val block: suspend () -> Unit = {
        outer(present)
        outer(empty)
    }
    val completion = Continuation<Unit>(EmptyCoroutineContext) { result -> result.getOrThrow() }
    block.startCoroutine(completion)
}
