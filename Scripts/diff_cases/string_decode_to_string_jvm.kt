// DIFF_JVM
fun main() {
    println(byteArrayOf(65, 66).decodeToString())
    println(byteArrayOf(0xE3.toByte(), 0x81.toByte(), 0x82.toByte()).decodeToString())
    println(byteArrayOf().decodeToString())

    val malformed = byteArrayOf(0xC3.toByte(), 0x28)
    println(malformed.decodeToString())
}
