fun main() {
    val iterableResult = sequenceOf(1, 2)
        .flatMapIndexed { index, value -> listOf(index, value * 10) }
        .toList()
    println(iterableResult)

    val sequenceResult = sequenceOf(1, 2)
        .flatMapIndexed { index, value -> sequenceOf(index + value, value * 100) }
        .toList()
    println(sequenceResult)

    val taken = sequenceOf(1, 2, 3)
        .flatMapIndexed { index, value -> sequenceOf(index, value) }
        .take(3)
        .toList()
    println(taken)

    println(emptySequence<Int>().flatMapIndexed { index, value -> listOf(index, value) }.toList())
}
