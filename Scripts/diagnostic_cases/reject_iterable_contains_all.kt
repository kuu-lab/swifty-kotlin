// EXPECT-REJECT
fun check(values: Iterable<Int>): Boolean = values.containsAll(listOf(1))

fun main() {
    val values: Iterable<Int> = sequenceOf(1, 2, 3).asIterable()
    println(values.containsAll(listOf(1, 2)))
    val widened: Iterable<Int> = listOf(1, 2, 3)
    println(widened.containsAll(emptyList<Int>()))
}
