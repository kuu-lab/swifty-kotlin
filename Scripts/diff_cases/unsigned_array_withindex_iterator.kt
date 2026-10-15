@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val bytes = UByteArray(2) { it.toUByte() }
    for ((index, value) in bytes.withIndex()) println("u8=$index:$value")
    val byteIterator: Iterator<UByte> = bytes.iterator()
    println("u8 iterator=${byteIterator.next()}:${byteIterator.hasNext()}")

    val shorts = UShortArray(2) { it.toUShort() }
    for ((index, value) in shorts.withIndex()) println("u16=$index:$value")
    val shortIterator: Iterator<UShort> = shorts.iterator()
    println("u16 iterator=${shortIterator.next()}:${shortIterator.hasNext()}")

    val ints = UIntArray(2) { it.toUInt() }
    for ((index, value) in ints.withIndex()) println("u32=$index:$value")
    val intIterator: Iterator<UInt> = ints.iterator()
    println("u32 iterator=${intIterator.next()}:${intIterator.hasNext()}")

    val longs = ULongArray(2) { it.toULong() }
    for ((index, value) in longs.withIndex()) println("u64=$index:$value")
    val longIterator: Iterator<ULong> = longs.iterator()
    println("u64 iterator=${longIterator.next()}:${longIterator.hasNext()}")
}
