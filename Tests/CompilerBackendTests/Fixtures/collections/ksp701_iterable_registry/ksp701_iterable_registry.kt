fun main() {
    val listValues: Iterable<Int> = listOf(1, 2, 3, 4)
    println(listValues.filter { it % 2 == 0 })
    println(listValues.reduce { acc, value -> acc + value })
    println(listValues.reduceIndexed { index, acc, value -> acc + index + value })

    val setValues: Iterable<Int> = setOf(1, 2, 3)
    println(setValues.filter { it > 1 }.size)
    println(setValues.reduce { acc, value -> acc + value })

    val rangeValues: Iterable<Int> = 1..3
    println(rangeValues.reduceIndexed { index, acc, value -> acc * 10 + value + index })
}
