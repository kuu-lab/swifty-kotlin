package diff

fun main() {
    var traversals = 0
    val values: Iterable<Int> = Iterable {
        traversals++
        listOf(3, 1, 2).iterator()
    }
    println(traversals)
    println(values.toList())
    println(values.toList())
    println(traversals)

    val empty: Iterable<String> = Iterable { emptyList<String>().iterator() }
    println(empty.toList())
}
