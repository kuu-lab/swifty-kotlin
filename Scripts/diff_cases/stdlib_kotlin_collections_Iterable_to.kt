// KSP-996: Iterable.to-family source-backed behavior and receiver isolation.

class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    private var consumed = false

    override fun iterator(): Iterator<T> {
        if (consumed) return listOf<T>().iterator()
        consumed = true
        return values.iterator()
    }
}

class FailingIterator : Iterator<Int> {
    private var index = 0

    override fun hasNext(): Boolean = index < 3

    override fun next(): Int {
        if (index == 1) throw IllegalStateException("boom")
        val result = index
        index += 1
        return result
    }
}

class FailingIterable : Iterable<Int> {
    override fun iterator(): Iterator<Int> = FailingIterator()
}

class FailingPairIterator : Iterator<Pair<Int, Int>> {
    private var index = 0

    override fun hasNext(): Boolean = index < 2

    override fun next(): Pair<Int, Int> {
        if (index == 1) throw IllegalStateException("pair-boom")
        val result = index to (index + 10)
        index += 1
        return result
    }
}

class FailingPairIterable : Iterable<Pair<Int, Int>> {
    override fun iterator(): Iterator<Pair<Int, Int>> = FailingPairIterator()
}

fun main() {
    val collectionDestination = mutableListOf<Int>(9)
    val collectionResult = OneShotIterable(listOf(1, 2, 2)).toCollection(collectionDestination)
    println(collectionResult === collectionDestination)
    println(collectionDestination)

    val nullableSource = OneShotIterable(listOf<String?>("a", null, "a", "b"))
    val hashSetResult = nullableSource.toHashSet()
    println(hashSetResult.size == 3 && hashSetResult.contains("a") && hashSetResult.contains(null))
    val firstHashSet = OneShotIterable(listOf(1, 2, 1)).toHashSet()
    val secondHashSet = OneShotIterable(listOf(1, 2, 1)).toHashSet()
    println(firstHashSet !== secondHashSet)
    println(firstHashSet.toList())
    val nullableSet = OneShotIterable(listOf<String?>("a", null, "a", "b")).toSet()
    println(nullableSet.size == 3 && nullableSet.contains("a") && nullableSet.contains(null))
    println(OneShotIterable(listOf(1, 2, 1)).toSet().toList())

    val emptyPairs: Iterable<Pair<String, Int>> = OneShotIterable(listOf())
    val singlePairs: Iterable<Pair<String, Int>> = OneShotIterable(listOf("one" to 1))
    val multiplePairs: Iterable<Pair<String?, Int?>> = OneShotIterable<Pair<String?, Int?>>(
        listOf<Pair<String?, Int?>>("a" to 1, "b" to 2, "a" to 3, null to null)
    )
    println(emptyPairs.toMap())
    println(singlePairs.toMap())
    println(multiplePairs.toMap())

    val destination: MutableMap<Any?, Any?> = mutableMapOf<Any?, Any?>("keep" to 9)
    val destinationPairs: Iterable<Pair<String?, Int?>> = OneShotIterable<Pair<String?, Int?>>(
        listOf<Pair<String?, Int?>>("a" to 1, "b" to 2, "a" to 3, null to null)
    )
    val returned = destinationPairs.toMap(destination)
    println(returned === destination)
    println(destination)

    val failingDestination = mutableListOf<Int>(9)
    try {
        FailingIterable().toCollection(failingDestination)
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println(failingDestination)

    val ordinaryLoopValues = mutableListOf<Int>()
    try {
        for (value in FailingIterable()) ordinaryLoopValues.add(value)
    } catch (e: IllegalStateException) {
        println("ordinary:${e.message}:$ordinaryLoopValues")
    }

    val destructuredLoopValues = mutableListOf<Int>()
    try {
        for ((left, right) in FailingPairIterable()) {
            destructuredLoopValues.add(left + right)
        }
    } catch (e: IllegalStateException) {
        println("destructuring:${e.message}:$destructuredLoopValues")
    }

    val explicitIteratorValues = mutableListOf<Int>()
    val explicitIterator = FailingIterable().iterator()
    try {
        while (explicitIterator.hasNext()) explicitIteratorValues.add(explicitIterator.next())
    } catch (e: IllegalStateException) {
        println("explicit:${e.message}:$explicitIteratorValues")
    }

    val nonThrowingLoopValues = mutableListOf<Int>()
    for (value in OneShotIterable(listOf(4, 5))) nonThrowingLoopValues.add(value)
    println("non-throwing:$nonThrowingLoopValues")

    println(listOf(1, 2, 1).toSet())
    println(sequenceOf(1, 2, 1).toSet())
    val textDestination = mutableListOf<Char>('!')
    println("ab".toCollection(textDestination) === textDestination)
    println(textDestination)
}
