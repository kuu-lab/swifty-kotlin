fun main() {
    val ascending = 1u..5u

    // Fold preserves the initial value and foldIndexed starts at zero.
    println(ascending.fold(10u) { accumulator, value -> accumulator + value })
    println(ascending.foldIndexed(10u) { index, accumulator, value -> accumulator + index.toUInt() * value })

    // Reduce uses the first element as the accumulator and reduceIndexed starts at one.
    println(ascending.reduce { accumulator, value -> accumulator + value })
    println(ascending.reduceIndexed { index, accumulator, value -> accumulator + index.toUInt() + value })

    ascending.forEach { print("$it ") }
    println()

    println(ascending.find { it % 2u == 0u })
    println(ascending.findLast { it % 2u == 0u })
    println(ascending.first { it > 3u })
    println(ascending.firstOrNull { it > 8u })
    println(ascending.last { it < 4u })
    println(ascending.lastOrNull { it > 8u })

    println(ascending.any { it == 5u })
    println(ascending.all { it > 0u })
    println(ascending.none { it > 5u })

    val empty = 5u..1u
    println(empty.fold(99u) { accumulator, value -> accumulator + value })
    try {
        println(empty.reduce { accumulator, value -> accumulator + value })
    } catch (e: Exception) {
        println("reduce on empty range threw: ${e.message}")
    }
    try {
        println(ascending.first { it > 8u })
    } catch (e: Exception) {
        println("first with no match threw: ${e.message}")
    }
}
