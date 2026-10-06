fun main() {
    val seq: Sequence<Int> = sequenceOf(1, 2, 3, 4)

    val mapDest = mutableListOf<String>()
    val mapped: MutableList<String> = seq.mapTo(mapDest) { it.toString() }

    val mapNotNullDest = mutableListOf<String>()
    val mappedNotNull: MutableList<String> = seq.mapNotNullTo(mapNotNullDest) {
        if (it % 2 == 0) it.toString() else null
    }

    val mapIndexedDest = mutableListOf<String>()
    val mappedIndexed: MutableList<String> = seq.mapIndexedTo(mapIndexedDest) { index, value ->
        index.toString() + ":" + value.toString()
    }

    val mapIndexedNotNullDest = mutableListOf<String>()
    val mappedIndexedNotNull: MutableList<String> = seq.mapIndexedNotNullTo(mapIndexedNotNullDest) { index, value ->
        if (index % 2 == 0) index.toString() + ":" + value.toString() else null
    }

    println(mapped)
    println(mappedNotNull)
    println(mappedIndexed)
    println(mappedIndexedNotNull)
}
