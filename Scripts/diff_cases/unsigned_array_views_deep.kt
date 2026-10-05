// KUU-1220: Views share storage but retain their own primitive array kind.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    println(arrayOf(byteArrayOf(-56, 1).asUByteArray()).contentDeepToString())
    println(arrayOf(ubyteArrayOf(200u).asByteArray()).contentDeepToString())
    val bytes = byteArrayOf(-56, 1)
    val view = bytes.asUByteArray()
    println(arrayOf(view).contentDeepEquals(arrayOf(ubyteArrayOf(200u, 1u))))
    println(arrayOf<Any>(bytes).contentDeepEquals(arrayOf<Any>(view)))
    println(arrayOf(view).contentDeepHashCode() == arrayOf(ubyteArrayOf(200u, 1u)).contentDeepHashCode())
    println(bytes === view.asByteArray())
    val copy = view.copyOf()
    bytes[0] = 42
    view[1] = 255u.toUByte()
    println(arrayOf<Any>(bytes, view, copy).contentDeepToString())
    val erased: Any = view
    println(erased is UByteArray)
    println(erased is ByteArray)

    val shorts = shortArrayOf(-1).asUShortArray()
    val ints = intArrayOf(-1).asUIntArray()
    val longs = longArrayOf(-1L).asULongArray()
    println(arrayOf<Any>(shorts, ints, longs).contentDeepToString())
    println(arrayOf<Any>(shorts, ints, longs).contentDeepEquals(
        arrayOf<Any>(ushortArrayOf(65535u), uintArrayOf(4294967295u), ulongArrayOf(18446744073709551615uL))))
    println(arrayOf<Any>(ushortArrayOf(65535u).asShortArray(),
        uintArrayOf(4294967295u).asIntArray(),
        ulongArrayOf(18446744073709551615uL).asLongArray()).contentDeepToString())
    val unsigned = uintArrayOf(4294967295u)
    val signed = unsigned.asIntArray()
    signed[0] = 7
    unsigned[0] = 9u
    println(arrayOf<Any>(unsigned, signed).contentDeepToString())
}
