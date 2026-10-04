fun main() {
    val bytes = byteArrayOf(1, -1, 0x7F, 0x80.toByte())
    val shorts = shortArrayOf(1, -1, 32767)
    println(bytes.size)
    println(bytes[1])
    println(bytes[3])
    println(shorts.size)
    println(shorts[2])

    bytes[0] = 9
    shorts[0] = 9
    println(bytes[0])
    println(shorts[0])
    println(bytes.binarySearch(0x80.toByte()))
    println(shorts.binarySearch(9))
}
