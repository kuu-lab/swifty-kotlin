@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val bytes = UByteArray(4) { (it * 100).toUByte() }
    val shorts = UShortArray(3) { (it + 1).toUShort() }
    val ints = UIntArray(2) { it.toUInt() }
    val longs = ULongArray(5) { it.toULong() }

    var sum = 0
    for (i in bytes.indices) sum += bytes[i].toInt()
    println(sum)
    println(bytes.indices)
    println(bytes.lastIndex)
    println(shorts.indices)
    println(shorts.lastIndex)
    println(ints.indices)
    println(ints.lastIndex)
    println(longs.indices)
    println(longs.lastIndex)
    println(UByteArray(0).indices.isEmpty())
    println(UByteArray(0).lastIndex)
}
