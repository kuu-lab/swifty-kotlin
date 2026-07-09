fun main() {
    println(listOf(1, 2, 3).firstOrNull())
    println(emptyList<Int>().firstOrNull())
    println(listOf(1, 2, 3).firstOrNull { it > 2 })
    println(listOf(1, 2, 3).firstOrNull { it > 10 })
    val firstPred: (Int) -> Boolean = { it > 2 }
    println(listOf(1, 2, 3).firstOrNull(firstPred))

    println(listOf(1, 2, 3).lastOrNull())
    println(emptyList<Int>().lastOrNull())
    println(listOf(1, 2, 3).lastOrNull { it < 3 })
    println(listOf(1, 2, 3).lastOrNull { it > 10 })
    val lastPred: (Int) -> Boolean = { it < 3 }
    println(listOf(1, 2, 3).lastOrNull(lastPred))
}
