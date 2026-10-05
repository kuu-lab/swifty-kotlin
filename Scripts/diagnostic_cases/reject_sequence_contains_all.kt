// EXPECT-REJECT
fun check(values: Sequence<Int>): Boolean = values.containsAll(listOf(1))

fun main() {
    val values = sequenceOf(1, 2, 3)
    println(values.containsAll(listOf(1, 2)))
    println(values.containsAll(listOf(9)))
    println(values.containsAll(emptyList<Int>()))
}
