// KUU-1421: signed<->unsigned primitive array copy conversions
// (ByteArray.toUByteArray family) were missing from the bundled stdlib.
// Unlike the asU*Array views, these return fresh storage; each element keeps
// its bit pattern. The case also pins that the result is a real copy: mutating
// either side does not leak into the other.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    // signed -> unsigned copies preserve bit patterns
    val bytes = byteArrayOf(1, -1, 0, 127, -128)
    val ubytes = bytes.toUByteArray()
    println(ubytes.toList())
    println(shortArrayOf(1, -1, 32767, -32768).toUShortArray().toList())
    println(longArrayOf(1L, -1L, 9223372036854775807L, -9223372036854775807L - 1).toULongArray().toList())

    // unsigned -> signed copies preserve bit patterns
    println(ubyteArrayOf(255.toUByte(), 0.toUByte(), 128.toUByte()).toByteArray().toList())
    println(ushortArrayOf(65535.toUShort(), 0.toUShort(), 32768.toUShort()).toShortArray().toList())
    println(uintArrayOf(4294967295u, 0u, 2147483648u).toIntArray().toList())
    println(ulongArrayOf(18446744073709551615uL, 0uL, 9223372036854775808uL).toLongArray().toList())

    // boxed Array<out U*> -> U*Array copies
    println(arrayOf(1.toUByte(), 255.toUByte()).toUByteArray().toList())
    println(arrayOf(1.toUShort(), 65535.toUShort()).toUShortArray().toList())
    println(arrayOf(1uL, 18446744073709551615uL).toULongArray().toList())

    // same-type copies return fresh storage too
    val uself = ubyteArrayOf(1.toUByte(), 255.toUByte())
    val uselfCopy = uself.toUByteArray()
    uself[0] = 9.toUByte()
    println(uselfCopy.toList())
    println(ushortArrayOf(1.toUShort()).toUShortArray().toList())
    println(uintArrayOf(1u).toUIntArray().toList())
    println(ulongArrayOf(1uL).toULongArray().toList())

    // copy semantics: mutating source does not affect result and vice versa
    val src = byteArrayOf(5, -5)
    val dst = src.toUByteArray()
    src[0] = 9
    dst[1] = 7.toUByte()
    println(src.toList())
    println(dst.toList())

    val usrc = ubyteArrayOf(200.toUByte())
    val udst = usrc.toByteArray()
    usrc[0] = 1.toUByte()
    udst[0] = 100
    println(usrc.toList())
    println(udst.toList())

    val boxedSrc = arrayOf(3.toUByte())
    val boxedDst = boxedSrc.toUByteArray()
    boxedSrc[0] = 4.toUByte()
    boxedDst[0] = 5.toUByte()
    println(boxedSrc.toList())
    println(boxedDst.toList())

    // empty arrays convert to empty arrays
    println(byteArrayOf().toUByteArray().toList())
    println(ubyteArrayOf().toByteArray().toList())
    println(arrayOf<UByte>().toUByteArray().toList())
    println(arrayOf<ULong>().toULongArray().toList())
}
