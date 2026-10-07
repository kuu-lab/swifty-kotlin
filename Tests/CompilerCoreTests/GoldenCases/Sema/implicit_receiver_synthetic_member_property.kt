fun main() {
    val l = listOf(1, 2, 3)
    println(l.run { lastIndex })
    with(l) { println(indices) }
}
