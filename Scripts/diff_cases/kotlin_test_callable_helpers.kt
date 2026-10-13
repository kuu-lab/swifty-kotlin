@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
import kotlin.test.*

fun <T> List<T>.choose(value: T): T = value
class Member { fun contains(value: Int): Boolean = value == 7 }
operator fun IntArray.get(first: Int, second: Int): Int = this[first] + second
operator fun IntArray.get(key: String): Int = this[key.length - 1]
fun String.pick(block: (Int, Int) -> Int): Int = block(2, 3)
fun describe(result: Result<Int>, prefix: String, marker: Int): String = result.fold(
    onSuccess = { "$prefix:$marker:$it" },
    onFailure = { return "$prefix:$marker:${it.message}" }
)
class CheckedRange : ClosedFloatingPointRange<Double> {
    override val start: Double = 1.0
    override val endInclusive: Double = 3.0
    override fun lessThanOrEquals(a: Double, b: Double): Boolean = a <= b
}
fun main() {
    val bound: (Any) -> Any = listOf("a")::choose
    val unbound: (List<String>, Any) -> Any = List<String>::choose
    println("widen:${bound(42)}:${unbound(listOf("a"), 43)}")
    val nullable: IntArray? = null
    val stringify = nullable::contentToString
    println("nullable:${stringify()}")
    val primitive = IntArray::get
    val erased = Array<*>::get
    println("get:${primitive(intArrayOf(7), 0)}:${erased(arrayOf("text"), 0)}")
    val contains: Member.(Int) -> Boolean = { false }
    println("member:${Member().contains(7)}")
    println("unsigned:${ubyteArrayOf(255u).contains(255u)}:${ushortArrayOf(65535u).contains(65535u)}:${uintArrayOf(UInt.MAX_VALUE).contains(UInt.MAX_VALUE)}:${ulongArrayOf(ULong.MAX_VALUE).contains(ULong.MAX_VALUE)}")
    println("array:${arrayOf(42).get(0)}:${arrayOf(42)::get.invoke(0)}")
    println("boolean:${BooleanArray::get.invoke(booleanArrayOf(true), 0)}")
    println("byte:${ByteArray::get.invoke(byteArrayOf((-1).toByte()), 0)}")
    println("char:${CharArray::get.invoke(charArrayOf('z'), 0)}")
    println("double:${DoubleArray::get.invoke(doubleArrayOf(1.5), 0)}")
    println("float:${FloatArray::get.invoke(floatArrayOf(1.5f), 0)}")
    println("long:${LongArray::get.invoke(longArrayOf(7L), 0)}")
    println("short:${ShortArray::get.invoke(shortArrayOf((-2).toShort()), 0)}")
    println("ubyte:${UByteArray::get.invoke(byteArrayOf((-1).toByte()).asUByteArray(), 0)}")
    println("ushort:${UShortArray::get.invoke(ushortArrayOf(65535u), 0)}")
    println("uint:${UIntArray::get.invoke(uintArrayOf(UInt.MAX_VALUE), 0)}")
    println("ulong:${ULongArray::get.invoke(ulongArrayOf(ULong.MAX_VALUE), 0)}")
    println("bounds:${assertFails { intArrayOf(1).get(1) } is IndexOutOfBoundsException}")
    println("extension:${intArrayOf(10)[0, 5]}:${intArrayOf(11)["x"]}")
    val pick: String.((Int) -> Int) -> Int = { it(7) }
    println("lambda:${"a".pick { a, b -> a + b }}")
    println("fold:${describe(Result.success(7), "ok", 42)}:${describe(Result.failure(IllegalStateException("failure")), "bad", 43)}")
    val range: ClosedRange<Double> = 1.0..3.0
    val containsRange = ClosedRange<Double>::contains
    val containsBound = range::contains
    val custom: ClosedFloatingPointRange<Double> = CheckedRange()
    println("range:${containsRange(range, 2.0)}:${containsBound(4.0)}:${containsRange(custom, 2.0)}:${custom::contains.invoke(4.0)}")
}
