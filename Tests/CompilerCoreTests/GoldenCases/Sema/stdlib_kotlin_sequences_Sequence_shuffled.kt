fun main() {
    val values: Sequence<Int> = sequenceOf(1, 2, 3)
    val shuffled: Sequence<Int> = values.shuffled()
    val shuffledWithRandom: Sequence<Int> = values.shuffled(kotlin.random.Random(1))
    println(shuffled.toList().size)
    println(shuffledWithRandom.toList().size)
}
