// KUU-1283: bundled comparator factories must preserve captured function values.
fun main() {
    val c = compareBy<Int> { it }
    println("made")
    println(c.compare(1, 2))
    println(listOf(3, 1, 2).sortedWith(compareBy<Int> { it }))
    println(listOf(3, 1, 2).sortedWith(compareByDescending { it }))
    val values = mutableListOf(3, 1, 2)
    values.sortWith(compareBy { -it })
    println(values)
    val tied = compareBy<Int> { it % 2 }
    println(listOf(3, 1, 2, 4).sortedWith(tied.thenBy { it }))
    println(listOf(3, 1, 2, 4).sortedWith(tied.thenByDescending { it }))
    println(listOf(3, 1, 2, 4).sortedWith(tied.thenComparator { a, b -> a.compareTo(b) }))
    println(naturalOrder<Int>().compare(1, 2))
    println(Comparator<Int> { a, b -> a - b }.compare(1, 2))
}
