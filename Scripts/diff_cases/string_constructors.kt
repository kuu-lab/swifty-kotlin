fun main() {
    val bytes = byteArrayOf(65, 66, 67)
    println(String(bytes))
    println(String(bytes, Charsets.UTF_8))
    println(String(byteArrayOf()).length)
}
