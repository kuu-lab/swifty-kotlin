fun main() {
    val prefix: String = "abcde".takeWhile { it != 'c' }
    println(prefix)
}
