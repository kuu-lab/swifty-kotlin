fun check(values: Collection<Int>) {
    println(values.containsAll(listOf(1, 2)))
    println(values.containsAll(listOf(9)))
    println(values.containsAll(emptyList<Int>()))
}

fun Iterable<Int>.containsAll(elements: Collection<Int>): Boolean {
    for (element in elements) {
        if (!contains(element)) return false
    }
    return true
}

fun Sequence<Int>.containsAll(elements: Collection<Int>): Boolean = toList().containsAll(elements)

fun main() {
    check(listOf(1, 2, 3))
    check(setOf(1, 2, 3))
    check(mutableListOf(1, 2, 3))
    check(mutableSetOf(1, 2, 3))

    val list = listOf(1, 2, 3)
    println(list.containsAll(listOf(1, 2)))
    println(list.containsAll(listOf(9)))
    val set = setOf(1, 2, 3)
    println(set.containsAll(listOf(1, 2)))
    println(set.containsAll(listOf(9)))

    val iterable: Iterable<Int> = list
    println(iterable.containsAll(listOf(1, 2)))
    println(iterable.containsAll(listOf(9)))
    println(iterable.containsAll(emptyList<Int>()))
    val sequence = sequenceOf(1, 2, 3)
    println(sequence.containsAll(listOf(1, 2)))
    println(sequence.containsAll(listOf(9)))
    println(sequence.containsAll(emptyList<Int>()))
}
