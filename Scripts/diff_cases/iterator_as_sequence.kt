// KSP-631: Iterator.asSequence must preserve the iterator, remain lazy, and
// enforce the one-shot contract while handling empty and partially consumed iterators.

class CountingIterator(private val values: List<Int>) : Iterator<Int> {
    private var index = 0
    var nextCalls = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): Int {
        if (!hasNext()) throw NoSuchElementException()
        nextCalls++
        val result = values[index]
        index++
        return result
    }
}

fun main() {
    val identityIterator = listOf(7).iterator()
    val identitySequence = identityIterator.asSequence()
    println(identitySequence.iterator() === identityIterator)
    println(identityIterator.next())

    val probe = CountingIterator(listOf(1, 2, 3))
    val lazySequence = probe.asSequence()
    println(probe.nextCalls)
    println(lazySequence.take(2).toList())
    println(probe.nextCalls)

    val oneShot = listOf(4, 5).iterator().asSequence()
    println(oneShot.toList())
    try {
        oneShot.toList()
        println("missing one-shot failure")
    } catch (e: IllegalStateException) {
        println("one-shot")
    }

    println(emptyList<Int>().iterator().asSequence().toList())

    val partial = CountingIterator(listOf(10, 20, 30))
    println(partial.next())
    println(partial.asSequence().toList())
}
