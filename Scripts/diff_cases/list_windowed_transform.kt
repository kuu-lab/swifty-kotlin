fun main() {
    val values = listOf(1, 2, 3, 4, 5)
    println(values.windowed(3) { it.sum() })
    println(values.windowed(2, 2) { it.joinToString("-") })
    println(values.windowed(3, 2, true) { it.size })
}
