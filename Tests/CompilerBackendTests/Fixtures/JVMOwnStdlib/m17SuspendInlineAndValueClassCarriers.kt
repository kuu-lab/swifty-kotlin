import kotlin.coroutines.*
@JvmInline value class Token(val bits: UInt)
class Gate {
    var pending: Continuation<UIntArray>? = null
    suspend fun await(): UIntArray = suspendCoroutine { pending = it }
    fun release() { pending!!.resume(uintArrayOf(4294967295u)) }
}
suspend fun byte(x: Byte): Byte = x
suspend fun char(x: Char): Char = x
suspend fun scalar(x: UInt = 4294967295u): UInt = x
suspend fun array(x: UIntArray): UIntArray = x
suspend fun nullableArray(x: UIntArray?): UIntArray? = x
inline suspend fun forward(x: UInt, action: suspend (UInt) -> UInt): UInt = action(x)
inline suspend fun forwardArray(x: UIntArray?): UIntArray? = nullableArray(x)
fun main() {
    val gate = Gate()
    val work: suspend () -> UInt = {
        println(byte(-128)); println(char('界')); println(scalar()); println(forward(4294967295u) { it / 2u })
        println(array(uintArrayOf(4294967295u))[0]); println(forwardArray(null)); println(forwardArray(uintArrayOf(3u))!![0])
        println(Token(4294967295u)); println(Token(4294967295u).hashCode())
        val result = gate.await(); println(result[0]); result[0]
    }
    work.startCoroutine(object: Continuation<UInt> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<UInt>) { println(result.getOrThrow()) }
    })
    println("paused"); gate.release()
}
