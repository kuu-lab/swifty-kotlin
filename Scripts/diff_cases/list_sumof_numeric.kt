fun main() {
    val values = listOf(1, 2, 3)
    println(values.sumOf { it })
    println(values.sumOf { it.toLong() })
    println(values.sumOf { it.toDouble() })
    println(emptyList<Int>().sumOf { it.toLong() })
    println(emptyList<Int>().sumOf { it.toDouble() })
}
