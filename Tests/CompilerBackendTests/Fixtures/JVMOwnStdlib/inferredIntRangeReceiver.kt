fun typed(range: IntRange, value: Int): Boolean = range.contains(value)

fun main() {
    val range = 0..10
    println(range.contains(5))
    println(5 in range)
    println(range.start)
    println(range.endInclusive)
    println(range is IntRange)
    println(typed(range, 7))
    var total = 0
    for (value in range) { total += value }
    println(total)
    println(range.toString())
}
