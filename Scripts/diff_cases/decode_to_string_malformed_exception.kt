fun main() {
    val bad = byteArrayOf(0x61, 0xE9.toByte(), 0x62)
    try {
        bad.decodeToString(0, 3, true)
        println("not thrown")
    } catch (e: Exception) {
        println(e.message)
        println(e is kotlin.text.CharacterCodingException)
        println(e.toString())
    }
}
