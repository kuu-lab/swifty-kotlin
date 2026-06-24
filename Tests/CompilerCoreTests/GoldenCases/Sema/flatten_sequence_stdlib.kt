fun main() {
    println(emptySequence<List<Int>>().flatten().toList())
    println(sequenceOf<List<Int>>().flatten().toList())

    println(sequenceOf(listOf<Int>(), listOf(1), listOf<Int>()).flatten().toList())

    val largeSeq = sequence {
        for (i in 1..10) {
            yield(listOf(i))
        }
    }
    val flattenedSeq = largeSeq.flatten().toList()
    println(flattenedSeq.size)
    println(flattenedSeq.take(5))
    println(flattenedSeq.drop(flattenedSeq.size - 5))

    val nestedSeq = sequenceOf(
        sequenceOf(1, 2),
        sequenceOf(3, 4)
    )
    println(nestedSeq.flatten().toList())

    val mixedSeq = sequenceOf(listOf(1, 2), sequenceOf(3, 4))
    println(mixedSeq.flatten().toList())

    val singleSeq = sequenceOf(listOf(42))
    println(singleSeq.flatten().toList())
}
