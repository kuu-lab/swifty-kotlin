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

    // KUU-1434: transform results must keep the Boolean/Char type tag across
    // the erased `R` boundary — nested List<Boolean> (ticket repro), a
    // capturing transform, and a transform stored in a val.
    val numbers = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    println(numbers.chunked(3) { chunk -> chunk.map { it % 2 == 0 } })
    println(numbers.windowed(3) { chunk -> chunk.map { it % 2 == 0 } })
    val limit = 2
    println(listOf(1, 2, 3, 4).chunked(2) { it.first() <= limit })
    val pred: (List<Int>) -> Boolean = { it.size == 2 }
    println(listOf(1, 2, 3, 4).chunked(2, pred))
    println(listOf('a', 'b', 'c', 'd').windowed(2) { it[0] })
}
