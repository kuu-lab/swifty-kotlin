fun main() {
    val ascii = byteArrayOf(72, 101, 108, 108, 111)
    println(ascii.decodeToString())

    val hiraganaA = byteArrayOf((-29).toByte(), (-127).toByte(), (-126).toByte())
    println(hiraganaA.decodeToString())

    val sliceSource = "abcdef".encodeToByteArray()
    println(sliceSource.decodeToString(1, 4))
    println(sliceSource.decodeToString(0, sliceSource.size, true))

    val malformed = byteArrayOf((-61).toByte(), 40.toByte())
    println(malformed.decodeToString(0, malformed.size, false))
    try {
        println(malformed.decodeToString(0, malformed.size, true))
    } catch (e: Throwable) {
        println("caught")
    }

    try {
        println(ascii.decodeToString(-1, 1))
    } catch (e: Throwable) {
        println("bounds")
    }
}
