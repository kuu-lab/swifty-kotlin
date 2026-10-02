fun main() {
    println(listOf(1, 3, 2).zipWithNext { a, b -> a < b })
    println(listOf(1, 2, 3).chunked(2) { it.size == 2 })
    println(listOf('x', 'y', 'z').windowed(2) { it[1] })
    println(listOf(1, 2, 3).windowed(2) { it.sum() > 3 })
    println(listOf(1, 2, 3).zip(listOf(3, 2, 1)) { a, b -> a < b })
    println(listOf('a', 'b').zip(listOf('c', 'd')) { a, b -> if (a < 'b') b else a })
    println(sequenceOf(1, 3, 2).zipWithNext { a, b -> a < b }.toList())
    println(sequenceOf(1, 2, 3).chunked(2) { it.size == 2 }.toList())
    println(sequenceOf('x', 'y', 'z').windowed(2) { it[1] }.toList())
    println(sequenceOf(1, 2, 3).zip(sequenceOf(3, 2, 1)) { a, b -> a < b }.toList())
    println(sequenceOf(1, 2, 3).map { it > 1 }.toList())
    println(sequenceOf(1, 2, 3).mapIndexed { i, v -> v > i }.toList())
}
