fun main() {
    val bytes = byteArrayOf(1, -1)
    val ubytes = bytes.asUByteArray()
    bytes[0] = -2
    println(ubytes[0].toInt())
    println(ubytes[1].toInt())
    println(ubytes.asByteArray()[0].toInt())

    val shorts = shortArrayOf(1, -1)
    val ushorts = shorts.asUShortArray()
    shorts[0] = -2
    println(ushorts[0].toInt())
    println(ushorts[1].toInt())
    println(ushorts.asShortArray()[0].toInt())

    val ints = intArrayOf(1, -1)
    val uints = ints.asUIntArray()
    ints[0] = -2
    println(uints[0].toString())
    println(uints[1].toString())
    println(uints.asIntArray()[0].toString())

    val longs = longArrayOf(1L, -1L)
    val ulongs = longs.asULongArray()
    longs[0] = -2L
    println(ulongs[0].toString())
    println(ulongs[1].toString())
    println(ulongs.asLongArray()[0].toString())
}
