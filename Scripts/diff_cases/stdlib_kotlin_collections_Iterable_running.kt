class CountingIterator(private val limit: Int) : Iterator<Int> {
    private var current = 0

    override fun hasNext(): Boolean = current < limit

    override fun next(): Int {
        if (current >= limit) throw IllegalStateException("over-consumed")
        val value = current
        current += 1
        return value
    }
}

class CountingIterable(private val limit: Int) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = CountingIterator(limit)
}

fun failOnTwo(value: Int): Int {
    if (value == 2) throw IllegalStateException("stop")
    return value
}

fun main() {
    val widened: Iterable<Int> = listOf(1, 2, 3)
    println(widened.runningReduce { acc, value -> acc + value })
    println(widened.runningReduceIndexed { index, acc, value -> acc + index + value })
    println(emptyList<Int>().runningReduce { acc, value -> acc + value })
    val singleton: Iterable<Int> = listOf(42)
    println(singleton.runningReduce { acc, value -> acc + value })

    val nullable: Iterable<String?> = listOf("a", null, "b")
    println(nullable.runningReduce { acc, value -> (acc ?: "") + (value ?: "") })

    val widenedAccumulator: Iterable<String> = listOf("a", "b")
    println(widenedAccumulator.runningReduce { acc: Any?, value -> acc.toString() + value })

    var calls = 0
    println(widened.runningReduce { acc, value ->
        calls += 1
        acc + value
    })
    println("calls=$calls")

    try {
        val oneShot: Iterable<Int> = CountingIterable(5)
        val stopped: List<Int> = oneShot.runningReduce { acc, value ->
            println("operation:$value")
            acc + failOnTwo(value)
        }
        println(stopped)
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    println(listOf(1, 2, 3).runningReduce { acc, value -> acc + value })
    println(listOf(1, 2, 3).asSequence().runningReduce { acc, value -> acc + value }.toList())
}
