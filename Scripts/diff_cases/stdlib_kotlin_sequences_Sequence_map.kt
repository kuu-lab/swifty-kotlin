fun main() {
    val seq = sequenceOf(1, 2, 3, 4)

    val mapDest = mutableListOf(99)
    println(seq.mapTo(mapDest) { it * 10 })

    val mapNotNullDest = mutableListOf(99)
    println(seq.mapNotNullTo(mapNotNullDest) { if (it % 2 == 0) it * 10 else null })

    val mapIndexedDest = mutableListOf(99)
    println(seq.mapIndexedTo(mapIndexedDest) { index, value -> index + value })

    val mapIndexedNotNullDest = mutableListOf(99)
    println(seq.mapIndexedNotNullTo(mapIndexedNotNullDest) { index, value ->
        if (index % 2 == 0) index + value else null
    })

    val strings = sequenceOf("a", "bb", "ccc")
    val lengths = mutableListOf<Int>()
    println(strings.mapTo(lengths) { it.length })
    println(lengths === strings.mapTo(lengths) { it.length })

    val emptyDest = mutableListOf(7)
    println(emptySequence<Int>().mapTo(emptyDest) { it * 2 })
    println(emptySequence<Int>().mapNotNullTo(emptyDest) { it * 2 })
    println(emptySequence<Int>().mapIndexedTo(emptyDest) { index, value -> index + value })
    println(emptySequence<Int>().mapIndexedNotNullTo(emptyDest) { index, value -> index + value })
}
