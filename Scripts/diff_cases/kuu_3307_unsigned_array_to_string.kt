@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

fun render(value: Any?): String = value.toString()

fun main() {
    val ulong = ulongArrayOf(0uL, 9223372036854775808uL, ULong.MAX_VALUE)
    val uint = uintArrayOf(0u, 2147483648u, UInt.MAX_VALUE)
    val ubyte = ubyteArrayOf(0u, 128u.toUByte(), UByte.MAX_VALUE)
    val ushort = ushortArrayOf(0u, 32768u.toUShort(), UShort.MAX_VALUE)

    println(ulongArrayOf().toString())
    println(ulong)
    println(ulong.toString())
    println(uint)
    println(uint.toString())
    println(ubyte)
    println(ubyte.toString())
    println(ushort)
    println(ushort.toString())
    println(render(ulong))
    println(render(uint))
    println(render(ubyte))
    println(render(ushort))
}
