private class StableIterable(private val values: List<Int>) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

fun main() {
    val addIterable: MutableCollection<Int> = mutableListOf(1)
    println(addIterable.addAll(StableIterable(listOf(2, 3))))
    println(addIterable)

    val addSequence: MutableCollection<Int> = mutableListOf(1)
    println(addSequence.addAll(sequenceOf(2, 3)))
    println(addSequence)

    val addArray: MutableCollection<Int> = mutableListOf(1)
    println(addArray.addAll(arrayOf(2, 3)))
    println(addArray)

    val plusTarget: MutableCollection<Int> = mutableListOf(1)
    plusTarget += 2
    plusTarget += StableIterable(listOf(3))
    plusTarget += sequenceOf(4)
    plusTarget += arrayOf(5)
    println(plusTarget)

    val removeElement: MutableCollection<Int> = mutableListOf(1, 2, 2, 3)
    println(removeElement.remove(2))
    println(removeElement)

    val minusTarget: MutableCollection<Int> = mutableListOf(1, 2, 2, 3, 4, 5)
    minusTarget -= 2
    minusTarget -= StableIterable(listOf(3))
    minusTarget -= sequenceOf(4)
    minusTarget -= arrayOf(5)
    println(minusTarget)

    val removeIterable: MutableCollection<Int> = mutableListOf(1, 2, 2, 3)
    println(removeIterable.removeAll(StableIterable(listOf(2))))
    println(removeIterable)

    val removeSequence: MutableCollection<Int> = mutableListOf(1, 2, 2, 3)
    println(removeSequence.removeAll(sequenceOf(2)))
    println(removeSequence)

    val removeArray: MutableCollection<Int> = mutableListOf(1, 2, 2, 3)
    println(removeArray.removeAll(arrayOf(2)))
    println(removeArray)

    val removeCollection: MutableCollection<Int> = mutableListOf(1, 2, 2, 3)
    val collectionInput: Collection<Int> = listOf(2)
    println(removeCollection.removeAll(collectionInput))
    println(removeCollection)

    val retainIterable: MutableCollection<Int> = mutableListOf(1, 2, 3)
    println(retainIterable.retainAll(StableIterable(listOf(2))))
    println(retainIterable)

    val retainSequence: MutableCollection<Int> = mutableListOf(1, 2, 3)
    println(retainSequence.retainAll(sequenceOf(2)))
    println(retainSequence)

    val retainArray: MutableCollection<Int> = mutableListOf(1, 2, 3)
    println(retainArray.retainAll(arrayOf(2)))
    println(retainArray)

    val retainCollection: MutableCollection<Int> = mutableListOf(1, 2, 3)
    val retainInput: Collection<Int> = listOf(2)
    println(retainCollection.retainAll(retainInput))
    println(retainCollection)

    val emptyRetain: MutableCollection<Int> = mutableListOf(1, 2)
    println(emptyRetain.retainAll(emptyArray<Int>()))
    println(emptyRetain)

    val nullable: MutableCollection<Int?> = mutableListOf(1, null, 1)
    println(nullable.remove(null))
    println(nullable)

    val set: MutableCollection<Int> = linkedSetOf(1, 2, 3)
    println(set.removeAll(arrayOf(2, 4)))
    println(set)
}
