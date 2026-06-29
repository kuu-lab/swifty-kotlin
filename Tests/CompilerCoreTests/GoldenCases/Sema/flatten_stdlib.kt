fun main() {
    println(listOf(listOf(1, 2), listOf(3, 4)).flatten())

    println(emptyList<List<Int>>().flatten())
    println(listOf(listOf<Int>()).flatten())
    println(listOf(listOf<Int>(), listOf<Int>()).flatten())

    println(listOf(listOf<Int>(), listOf(1), listOf<Int>()).flatten())

    println(listOf(listOf(42)).flatten())

    println(listOf(listOf("a", "b"), listOf("c")).flatten())
    println(listOf(listOf<String>(), listOf("x")).flatten())

    val large = (1..10).map { listOf(it) }
    println(large.flatten().size)
    println(large.flatten().take(3))
}
