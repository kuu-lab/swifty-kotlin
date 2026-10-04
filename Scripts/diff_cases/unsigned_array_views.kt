// KSP-660: Array unsigned/signed view conversions (asUByteArray/asByteArray and siblings).
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    // Signed -> unsigned views share the same backing storage.
    val bytes = byteArrayOf(1, 2, 3)
    val ubytes = bytes.asUByteArray()
    bytes[1] = 9
    println(ubytes.toList())

    val shorts = shortArrayOf(10, 20)
    println(shorts.asUShortArray().toList())

    val ints = intArrayOf(100, 200)
    println(ints.asUIntArray().toList())

    val longs = longArrayOf(1000L, 2000L)
    println(longs.asULongArray().toList())

    // Unsigned -> signed views share the same backing storage.
    val ub = ubyteArrayOf(1.toUByte(), 2.toUByte(), 3.toUByte())
    val sb = ub.asByteArray()
    ub[1] = 9.toUByte()
    println(sb.toList())

    println(ushortArrayOf(10.toUShort(), 20.toUShort()).asShortArray().toList())
    println(uintArrayOf(100u, 200u).asIntArray().toList())
    println(ulongArrayOf(1000uL, 2000uL).asLongArray().toList())
}
