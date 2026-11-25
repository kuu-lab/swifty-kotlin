fun main() {
    val removeListArray = mutableListOf(1, 2, 3, 4)
    println(removeListArray.removeAll(arrayOf(2, 4)))
    println(removeListArray)
    println(removeListArray.removeAll(arrayOf(2, 4)))
    println(removeListArray)

    val retainListArray = mutableListOf(1, 2, 3, 4)
    println(retainListArray.retainAll(arrayOf(2, 4)))
    println(retainListArray)

    val removeListSequence = mutableListOf(1, 2, 3, 4)
    println(removeListSequence.removeAll(sequenceOf(2, 4)))
    println(removeListSequence)

    val retainListSequence = mutableListOf(1, 2, 3, 4)
    println(retainListSequence.retainAll(sequenceOf(2, 4)))
    println(retainListSequence)

    val removeSetSequence = mutableSetOf(1, 2, 3, 4)
    println(removeSetSequence.removeAll(sequenceOf(2, 4)))
    println(removeSetSequence)

    val retainSetSequence = mutableSetOf(1, 2, 3, 4)
    println(retainSetSequence.retainAll(sequenceOf(2, 4)))
    println(retainSetSequence)

    val removeSetArray = mutableSetOf(1, 2, 3, 4)
    println(removeSetArray.removeAll(arrayOf(2, 4)))
    println(removeSetArray)

    val retainSetArray = mutableSetOf(1, 2, 3, 4)
    println(retainSetArray.retainAll(arrayOf(2, 4)))
    println(retainSetArray)

    val retainEmptyArray = mutableListOf(1, 2, 3)
    println(retainEmptyArray.retainAll(emptyArray<Int>()))
    println(retainEmptyArray)

    val retainEmptySequence = mutableSetOf(1, 2, 3)
    println(retainEmptySequence.retainAll(emptySequence<Int>()))
    println(retainEmptySequence)

    val removeEmptyArray = mutableListOf(1, 2, 3)
    println(removeEmptyArray.removeAll(emptyArray<Int>()))
    println(removeEmptyArray)
}
