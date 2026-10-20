fun <T> same(x: T): T = x
inline fun <reified T> matches(x: Any): Boolean = x is T
fun maybe(x: UInt?): UInt? = x
fun unsignedIdentity(x: UInt): UInt = x
fun arrayMaybe(x: UIntArray?): UIntArray? = x
fun main() {
    val bytes = ubyteArrayOf(0u, 255u); bytes[0] = 254u; println(bytes[0]); println(bytes[1])
    val shorts = ushortArrayOf(65535u); println(shorts[0].toInt())
    val ints = UIntArray(2) { i -> i.toUInt() + 4294967294u }; println(ints[0]); println(ints[1])
    val longs = ulongArrayOf(18446744073709551615uL); println(longs[0] / 2uL)
    var total = 0u; for (item in bytes) { total += item }; println(total)
    println(ints.map { it.toLong() }); println(same(bytes)[1]); println(same(255u.toUByte()))
    val values = listOf(0u, 4294967295u); println(values); println(values[1] > values[0])
    println(maybe(null)); println(maybe(4294967295u)); println(maybe(2u)!! + 1u)
    println(arrayMaybe(null)); println(arrayMaybe(ints)!![1])
    val boxed: Any = 4294967295u; println(boxed is UInt); println(matches<UInt>(boxed)); println(matches<Int>(boxed))
    val c: Char = same('界'); val b: Byte = same(127.toByte()); println(c); println(b)
    var captured = 255u.toUByte(); val next = { captured++; captured }; println(next()); println(next())
    println(UInt::class.simpleName); println(Char::class.simpleName)
    val reference = ::unsignedIdentity; println(reference.name); println(reference(4294967295u))
}
