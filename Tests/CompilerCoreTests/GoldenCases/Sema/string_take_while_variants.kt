fun main() {
    val prefix: String = "abcde".takeWhile { it != 'c' }
    val suffix: String = "abc123".takeLastWhile { it.isDigit() }
    println(prefix)
    println(suffix)
}
