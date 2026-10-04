// KSP-1513: unsigned array size/toList/asList and generic Array<T> conversions.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val ubytes = ubyteArrayOf(1.toUByte(), 2.toUByte())
    val ubyteCopy = ubytes.toList()
    val ubyteView = ubytes.asList()
    ubytes[0] = 9.toUByte()
    println(ubytes.size)
    println(ubyteCopy)
    println(ubyteView)

    val ushorts = ushortArrayOf(3.toUShort(), 4.toUShort())
    val ushortCopy = ushorts.toList()
    val ushortView = ushorts.asList()
    ushorts[0] = 8.toUShort()
    println(ushorts.size)
    println(ushortCopy)
    println(ushortView)

    val uints = uintArrayOf(5u, 6u)
    val uintCopy = uints.toList()
    val uintView = uints.asList()
    uints[0] = 7u
    println(uints.size)
    println(uintCopy)
    println(uintView)

    val ulongs = ulongArrayOf(10uL, 11uL)
    val ulongCopy = ulongs.toList()
    val ulongView = ulongs.asList()
    ulongs[0] = 12uL
    println(ulongs.size)
    println(ulongCopy)
    println(ulongView)

    val objects = arrayOf("a", "b")
    val objectCopy: List<String> = objects.toList()
    objects[0] = "z"
    println(objects.size)
    println(objectCopy)
}
