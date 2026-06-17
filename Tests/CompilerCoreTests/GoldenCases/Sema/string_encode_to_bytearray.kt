fun main() {
    val s = "Hello"
    val bytes1 = s.encodeToByteArray()
    val bytes2 = s.encodeToByteArray(1, 4)
    val bytes3 = s.encodeToByteArray(Charsets.UTF_8)
    println(bytes1.size)
    println(bytes2.size)
    println(bytes3.size)
}
