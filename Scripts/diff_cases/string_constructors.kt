fun main() {
    val bytes = byteArrayOf(65, 66, 67)
    val chars = charArrayOf('A', 'B', 'C')
    println(String(bytes))
    println(String(bytes, Charsets.UTF_8))
    println(String(byteArrayOf()).length)
    println(String(chars))
    println(String(chars, 1, 2))
}
