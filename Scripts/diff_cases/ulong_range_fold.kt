fun main() {
    val ascending = 1UL..5UL

    // Fold preserves the initial value and foldIndexed starts at zero.
    println(ascending.fold(10UL) { accumulator, value -> accumulator + value })
    println(ascending.foldIndexed(10UL) { index, accumulator, value -> accumulator + index.toULong() * value })

    // Reduce uses the first element as the accumulator and reduceIndexed starts at one.
    println(ascending.reduce { accumulator, value -> accumulator + value })
    println(ascending.reduceIndexed { index, accumulator, value -> accumulator + index.toULong() + value })

    ascending.forEach { print("$it ") }
    println()

    println(ascending.find { it % 2UL == 0UL })
    println(ascending.findLast { it % 2UL == 0UL })
    println(ascending.first { it > 3UL })
    println(ascending.firstOrNull { it > 8UL })
    println(ascending.last { it < 4UL })
    println(ascending.lastOrNull { it > 8UL })

    println(ascending.any { it == 5UL })
    println(ascending.all { it > 0UL })
    println(ascending.none { it > 5UL })

    val empty = 5UL..1UL
    println(empty.fold(99UL) { accumulator, value -> accumulator + value })
    try {
        println(empty.reduce { accumulator, value -> accumulator + value })
    } catch (e: Exception) {
        println("reduce on empty range threw: ${e.message}")
    }
    try {
        println(ascending.first { it > 8UL })
    } catch (e: Exception) {
        println("first with no match threw: ${e.message}")
    }
}
