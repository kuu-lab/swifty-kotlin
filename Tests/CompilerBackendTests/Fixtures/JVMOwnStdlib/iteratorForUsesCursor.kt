fun main() {
    val builder = iterator<Int> { yield(1); yield(2) }
    for (value in builder) println(value)
    val offset = 10
    val captured = iterator<Int> { for (value in 1..2) yield(value + offset) }
    for (value in captured) println(value)
    val ordinary: Iterator<Int> = listOf(3, 4).iterator()
    for (value in ordinary) println(value)
    for (value in iterator<Int> {}) println("unexpected")
    val direct = iterator<Int> { yield(5) }
    while (direct.hasNext()) println(direct.next())
    for (value in sequence<Int> { yield(6) }) println(value)
    for (value in listOf(7)) println(value)
    for (value in arrayOf(8)) println(value)
    for (value in "a") println(value)
    for (value in 9..10) println(value)
    val primitive = kotlin.ranges.IntRange(12, 13).iterator()
    for (value in primitive) println(value)
}
