// KSP-974: Keep this case statically typed as Iterable so List-specific
// implementations cannot satisfy the calls accidentally.
class OneShotIntIterable(private val value: Int) : Iterable<Int> {
    private var consumed = false

    override fun iterator(): Iterator<Int> {
        if (consumed) throw IllegalStateException("outer iterable reused")
        consumed = true
        return listOf(value, value + 1).iterator()
    }
}

class OneShotInnerIterable(private val value: Int) : Iterable<Int> {
    private var consumed = false

    override fun iterator(): Iterator<Int> {
        if (consumed) throw IllegalStateException("inner iterable reused")
        consumed = true
        return listOf(value, value * 10).iterator()
    }
}

fun main() {
    val source: Iterable<Int> = listOf(1, 2, 3)

    println(source.flatMap { value -> listOf(value, value * 10) })
    println(source.flatMap { value -> sequenceOf(value + 100, value + 200) })
    println(source.flatMapIndexed { index, value -> listOf(index, value) })
    println(source.flatMapIndexed { index, value -> sequenceOf(index + 10, value + 10) })

    val iterableDestination: MutableList<Any?> = mutableListOf("seed-i")
    val iterableReturned = source.flatMapTo(iterableDestination) { value -> listOf(value) }
    println(iterableReturned)
    println(iterableReturned === iterableDestination)

    val sequenceDestination: MutableList<Any?> = mutableListOf("seed-s")
    val sequenceReturned = source.flatMapTo(sequenceDestination) { value -> sequenceOf(value * 2) }
    println(sequenceReturned)
    println(sequenceReturned === sequenceDestination)

    val indexedIterableDestination: MutableList<Any?> = mutableListOf("seed-ii")
    val indexedIterableReturned = source.flatMapIndexedTo(indexedIterableDestination) { index, value -> listOf(index, value) }
    println(indexedIterableReturned)
    println(indexedIterableReturned === indexedIterableDestination)

    val indexedSequenceDestination: MutableList<Any?> = mutableListOf("seed-is")
    val indexedSequenceReturned = source.flatMapIndexedTo(indexedSequenceDestination) { index, value -> sequenceOf(index, value * 3) }
    println(indexedSequenceReturned)
    println(indexedSequenceReturned === indexedSequenceDestination)

    var sequenceTransformCalls = 0
    val eagerSequenceResult = source.flatMap { value ->
        sequenceTransformCalls += 1
        if (value == 2) emptySequence<Int>() else sequenceOf(value, value + 10)
    }
    println(eagerSequenceResult)
    println(sequenceTransformCalls)

    val firstResult = source.flatMap { value -> listOf(value) }
    val secondResult = source.flatMap { value -> listOf(value) }
    println(firstResult)
    println(firstResult === secondResult)

    val indexedWithEmpty = source.flatMapIndexed { index, value ->
        if (value == 2) emptyList<String>() else listOf(index.toString() + ":" + value.toString())
    }
    println(indexedWithEmpty)

    val nullableSource: Iterable<Int?> = listOf(1, null)
    println(nullableSource.flatMap { value -> listOf(value, null) })

    val oneShotOuter: Iterable<Int> = OneShotIntIterable(7)
    println(oneShotOuter.flatMap { value -> OneShotInnerIterable(value) })

    var visited = 0
    try {
        source.flatMap { value ->
            visited += 1
            if (value == 2) throw IllegalStateException("stop")
            listOf(value)
        }
    } catch (e: IllegalStateException) {
        println("caught:" + visited)
    }
}
