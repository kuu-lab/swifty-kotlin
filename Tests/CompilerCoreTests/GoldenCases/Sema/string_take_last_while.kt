fun main() {
    val suffix: String = "abc123".takeLastWhile { it.isDigit() }
    println(suffix)
}
