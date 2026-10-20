import kotlin.coroutines.*
class Choice(val number: UInt, val bytes: UByteArray)
class Gate {
    var pending: Continuation<UIntArray?>? = null
    suspend fun await(): UIntArray? = suspendCoroutine { pending = it }
    fun release() { pending!!.resume(null) }
}
data class Data(val values: UIntArray, val b: UByte, val s: Byte)
@JvmInline value class Values(val value: UIntArray)
suspend fun forward(gate: Gate): UIntArray? = gate.await()
suspend fun returnsNull(gate: Gate): UIntArray? { gate.await(); return null }
const val MAX: UInt = 4294967295u
fun main() {
    val choice = Choice(4294967295u, ubyteArrayOf(255u)); println(choice.number); println(choice.bytes[0])
    val missing: UIntArray? = null; val erased: Any? = missing; println(erased == null)
    val list = listOf(missing); println(list[0] == null)
    val array = arrayOf<UIntArray?>(null); println(array[0] == null); array[0] = missing; println(array[0] == null)
    val gate = Gate()
    val first: suspend () -> UIntArray? = { forward(gate) }
    val second: suspend () -> UIntArray? = { returnsNull(gate) }
    val completion = object: Continuation<UIntArray?> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<UIntArray?>) { println(result.getOrThrow() == null) }
    }
    first.startCoroutine(completion); gate.release(); second.startCoroutine(completion); gate.release()
    val values = uintArrayOf(4294967295u, 1u)
    val data = Data(values, 255u, -1); println(data); println(data.hashCode())
    println(Values(values)); println(Values(values).hashCode())
    val small: UByte = 255u; println(small.hashCode()); println(MAX)
    try { missing!!; println("bad") } catch (e: NullPointerException) { println("null asserted") }
    val tiny: Byte? = -128; val medium: Short? = 32767; println(tiny); println(medium)
}
