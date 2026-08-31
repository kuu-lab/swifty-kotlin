package golden.sema

fun main() {
    val ubytes = ubyteArrayOf(1.toUByte(), 2.toUByte(), 3.toUByte())
    val ushorts = ushortArrayOf(4.toUShort(), 5.toUShort(), 6.toUShort())
    val uints = uintArrayOf(7u, 8u, 9u)
    val ulongs = (10uL..12uL).toULongArray()

    val ubyteList = ubytes.asList()
    val ushortList = ushorts.asList()
    val uintList = uints.asList()
    val ulongList = ulongs.asList()

    val ubyteSize: Int = ubytes.size
    val ubyteCopy: List<UByte> = ubytes.toList()
    val ushortSize: Int = ushorts.size
    val ushortCopy: List<UShort> = ushorts.toList()
    val uintSize: Int = uints.size
    val uintCopy: List<UInt> = uints.toList()
    val ulongSize: Int = ulongs.size
    val ulongCopy: List<ULong> = ulongs.toList()

    val objects = arrayOf(1, 2)
    val objectSize: Int = objects.size
    val objectCopy: List<Int> = objects.toList()

    println(ubyteList)
    println(ushortList)
    println(uintList)
    println(ulongList)
}
