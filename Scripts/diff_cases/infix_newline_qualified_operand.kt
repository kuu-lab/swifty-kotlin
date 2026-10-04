fun main() {
    val bytes = byteArrayOf(0xe2.toByte(), 0x82.toByte(), 0xac.toByte())
    val codePoint = -0x01e080 xor bytes[2].toInt() xor
        (bytes[1].toInt() shl 6) xor (bytes[0].toInt() shl 12)
    println(codePoint)
    val ints = intArrayOf(2)
    val indexed = 1 or ints[0] and
        0xff
    println(indexed)
    val property = 1 or bytes.size or
        4
    println(property)
    val grouped = 1 or (2) or
        (4)
    println(grouped)
    val complete = 1 or bytes.size
    (8).toInt()
    println(complete)
}
