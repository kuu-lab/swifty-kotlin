fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)

    println(values.reduceRightOrNull { value, acc ->
        value * 10 + acc
    } ?: -1)
    println(listOf(7).reduceRightOrNull { value, acc ->
        value + acc
    } ?: -1)
    println(emptyList<Int>().reduceRightOrNull { value, acc ->
        value + acc
    } ?: -1)
}
