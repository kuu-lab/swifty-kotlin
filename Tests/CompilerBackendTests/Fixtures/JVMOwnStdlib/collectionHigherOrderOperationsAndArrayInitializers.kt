fun main() {
    var total = 0
    val mapped = listOf(1, 2, 3).map { it * 2 }.filter { it > 2 }
    mapped.forEach { value -> if (value == 4) return@forEach; total += value }
    println(total)
    println(mapped.fold(10) { sum, value -> sum + value })
    val values = IntArray(3) { index -> index + 1 }
    println(values.fold(0) { sum, value -> sum + value })
    val words = Array<String>(2) { index -> if (index == 0) "first" else "second" }
    words.forEach { println(it) }
    val emit: (String) -> Unit = { println(it) }
    words.forEach(emit)
    val action: () -> Unit = { println("unit") }
    action()
    val square: (Int) -> Int = { it * it }
    val squared = values.map(square)
    println(squared[2])
}
