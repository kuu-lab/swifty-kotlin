fun main() {
    val bytes = byteArrayOf(1, -1)
    val ubytes = bytes.asUByteArray()
    bytes[0] = -2
    println(ubytes[0].toInt())
    println(ubytes[1].toInt())
    val signedBytes = ubytes.asByteArray()
    println(signedBytes[0].toInt())
    signedBytes[1] = 3
    println(bytes[1].toInt())

    val shorts = shortArrayOf(1, -1)
    val ushorts = shorts.asUShortArray()
    shorts[0] = -2
    println(ushorts[0].toInt())
    println(ushorts[1].toInt())
    val signedShorts = ushorts.asShortArray()
    println(signedShorts[0].toInt())
    signedShorts[1] = 3
    println(shorts[1].toInt())

    val ints = intArrayOf(1, -1)
    val uints = ints.asUIntArray()
    ints[0] = -2
    println(uints[0].toString())
    println(uints[1].toString())
    val signedInts = uints.asIntArray()
    println(signedInts[0].toString())
    signedInts[1] = 3
    println(ints[1].toString())

    val longs = longArrayOf(1L, -1L)
    val ulongs = longs.asULongArray()
    longs[0] = -2L
    println(ulongs[0].toString())
    println(ulongs[1].toString())
    val signedLongs = ulongs.asLongArray()
    println(signedLongs[0].toString())
    signedLongs[1] = 3
    println(longs[1].toString())
}
