fun inspect(values: Collection<Int>, other: Collection<Int>): Boolean {
    val size = values.size
    val empty = values.isEmpty()
    val member = values.contains(2)
    val all = values.containsAll(other)
    val iterator = values.iterator()
    return size >= 0 && (empty || member || all || iterator.hasNext())
}

fun main() {
    val values: Collection<Int> = listOf(1, 2, 3)
    val other: Collection<Int> = listOf(1, 3)
    println(inspect(values, other))
    println(inspect(emptyList(), listOf(1)))
}
