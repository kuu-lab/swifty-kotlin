fun probeBuilder(iterator: Iterator<Int>, useNext: Boolean) {
    try {
        if (useNext) println(iterator.next()) else println(iterator.hasNext())
    } catch (e: IllegalArgumentException) {
        println("argument: ${e.message}")
    } catch (e: IllegalStateException) {
        println("state: ${e.message}")
    }
}

fun main() {
    val failed: Iterator<Int> = iterator<Int> { throw IllegalArgumentException("boom") }
    probeBuilder(failed, false)
    probeBuilder(failed, false)
    probeBuilder(failed, true)

    val failedNext: Iterator<Int> = iterator<Int> { yield(7); throw IllegalArgumentException("after yield") }
    probeBuilder(failedNext, true)
    probeBuilder(failedNext, true)
    probeBuilder(failedNext, false)
    probeBuilder(failedNext, true)

    val built: Sequence<Int> = sequence<Int> { throw IllegalArgumentException("sequence boom") }
    val sequenceIterator: Iterator<Int> = built.iterator()
    probeBuilder(sequenceIterator, false)
    probeBuilder(sequenceIterator, false)
    probeBuilder(sequenceIterator, true)
    probeBuilder(built.iterator(), true)

    try {
        sequence<Int> { yieldAll(iterator<Int> { throw IllegalStateException("nested") }) }.toList()
    } catch (e: IllegalStateException) { println(e.message) }
    try {
        sequence<Int> {
            yield(1)
            yieldAll(iterator<Int> { yield(2); throw IllegalArgumentException("nested after yield") })
            yield(3)
        }.toList()
    } catch (e: IllegalArgumentException) { println(e.message) }
    try {
        sequence<Int> {
            yieldAll(sequence<Int> { yield(4); throw IllegalArgumentException("nested sequence") })
        }.toList()
    } catch (e: IllegalArgumentException) { println(e.message) }

    val empty: Iterator<Int> = iterator<Int> { }
    probeBuilder(empty, false)
    probeBuilder(empty, false)
    try { empty.next() } catch (e: NoSuchElementException) { println("exhausted") }
    println(sequence<Int> { yieldAll(listOf(5, 6)); yield(7) }.toList())
}
