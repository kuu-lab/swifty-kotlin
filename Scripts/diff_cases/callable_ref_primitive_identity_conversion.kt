// References to numeric conversions that are the identity (`Int::toInt`) or a
// pure widening of the same raw representation (`Byte::toInt`, `Short::toLong`)
// have no runtime symbol of their own. Taking them as callable references used
// to leave a call to the Sema-only sentinel behind and fail to link.
fun <T, R> applyTo(value: T, transform: (T) -> R): R = transform(value)

fun main() {
    val i: Int = -70000
    val b: Byte = -5
    val s: Short = -300
    val l: Long = -5000000000L
    val d: Double = -3.5
    val f: Float = 2.25f
    val ub: UByte = 250u
    val us: UShort = 60000u
    val ui: UInt = 4000000000u
    val ul: ULong = 18000000000000000000uL

    // Unbound references, called directly.
    println((Int::toInt)(i))
    println((Byte::toInt)(b))
    println((Byte::toLong)(b))
    println((Byte::toShort)(b))
    println((Short::toInt)(s))
    println((Short::toLong)(s))
    println((Long::toLong)(l))
    println((Double::toDouble)(d))
    println((Float::toFloat)(f))
    println((UByte::toUByte)(ub))
    println((UShort::toUShort)(us))
    println((UInt::toUInt)(ui))
    println((ULong::toULong)(ul))

    // Bound references.
    println(i::toInt.invoke())
    println(b::toInt.invoke())
    println(s::toLong.invoke())

    // References handed to higher-order functions.
    println(listOf(b, 7.toByte()).map(Byte::toInt))
    println(listOf(i, 3).map(Int::toInt))
    println(applyTo(s, Short::toInt))
    println(applyTo(l, Long::toLong))
    println(applyTo(d, Double::toDouble))
}
