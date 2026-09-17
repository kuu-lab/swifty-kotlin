fun main() {
    println((1uL..5uL).map { it * 2uL })
    println((1uL..5uL).mapIndexed { index, value -> index.toULong() + value })
    println((1uL..5uL).mapNotNull { if (it % 2uL == 0uL) null else it })
    println((1uL..5uL).filter { it % 2uL == 1uL })
    println((1uL..5uL).filterIndexed { index, _ -> index % 2 == 0 })
    println((1uL..5uL).filterNot { it % 2uL == 0uL })
    println((5uL..1uL).mapNotNull { it })
    println((5uL..1uL).filterIndexed { index, _ -> index == 0 })
    println((5uL downTo 1uL).mapIndexed { index, value -> index.toULong() + value })
    println((5uL downTo 1uL).filterNot { it % 2uL == 0uL })
    println((1uL..9uL step 2).mapIndexed { index, value -> index.toULong() + value })
    println((1uL..9uL step 2).filterNot { it > 4uL })
}
