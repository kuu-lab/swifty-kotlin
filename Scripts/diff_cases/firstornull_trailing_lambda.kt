fun main() {
    println(listOf(1, 2, 3).firstOrNull { it > 2 })
    println(listOf(1, 2, 3).firstOrNull { it > 10 })
    val pred: (Int) -> Boolean = { it > 2 }
    println(listOf(1, 2, 3).firstOrNull(pred))
}
