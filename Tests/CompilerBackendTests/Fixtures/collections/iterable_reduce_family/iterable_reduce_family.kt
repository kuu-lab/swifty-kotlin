open class ReduceBase(val value: Int) {
    override fun toString(): String = value.toString()
}

class ReduceChild(value: Int) : ReduceBase(value)

class ReduceChildIterator(private val values: List<ReduceChild>) : Iterator<ReduceChild> {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): ReduceChild = values[index++]
}

class ReduceChildIterable(private val values: List<ReduceChild>) : Iterable<ReduceChild> {
    override fun iterator(): Iterator<ReduceChild> = ReduceChildIterator(values)
}

class ProbeIterator(private val values: List<Int>) : Iterator<Int> {
    private var index = 0
    var nextCalls = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): Int {
        nextCalls += 1
        return values[index++]
    }
}

class ProbeIterable(private val values: List<Int>) : Iterable<Int> {
    val iteratorValue = ProbeIterator(values)
    var iteratorCalls = 0

    override fun iterator(): Iterator<Int> {
        iteratorCalls += 1
        return iteratorValue
    }
}

fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3, 4)
    println(values.reduce { acc, value -> acc + value })
    println(values.reduceIndexed { index, acc, value -> acc + index * value })

    val empty: Iterable<Int> = emptyList()
    println(empty.reduceOrNull { acc, value -> acc + value })
    println(empty.reduceIndexedOrNull { index, acc, value -> acc + index + value })
    try {
        empty.reduce { acc, value -> acc + value }
        println("missing empty reduce exception")
    } catch (e: UnsupportedOperationException) {
        println("empty reduce")
    }
    try {
        empty.reduceIndexed { index, acc, value -> acc + index + value }
        println("missing empty reduceIndexed exception")
    } catch (e: UnsupportedOperationException) {
        println("empty reduceIndexed")
    }

    val singleton: Iterable<Int> = listOf(42)
    println(singleton.reduce { acc, value -> acc + value })
    println(singleton.reduceIndexed { index, acc, value -> acc + index + value })
    var operationCalls = 0
    println(singleton.reduceOrNull { acc, value -> operationCalls += 1; acc + value })
    println(operationCalls)
    println(singleton.reduceIndexedOrNull { index, acc, value -> operationCalls += index; acc + value })
    println(operationCalls)

    val nullable: Iterable<String?> = listOf(null, "x", null)
    println(nullable.reduceOrNull { acc, value -> acc ?: value })

    val polymorphic: Iterable<ReduceChild> = ReduceChildIterable(
        listOf(ReduceChild(1), ReduceChild(2), ReduceChild(3), ReduceChild(4))
    )
    val widenOperation: (ReduceBase, ReduceChild) -> ReduceBase = { acc, value ->
        ReduceBase(acc.value + value.value)
    }
    val widened: ReduceBase = polymorphic.reduce(widenOperation)
    val widenIndexedOperation: (Int, ReduceBase, ReduceChild) -> ReduceBase = { index, acc, value ->
        ReduceBase(acc.value + index + value.value)
    }
    val widenedIndexed: ReduceBase? = polymorphic.reduceIndexedOrNull(widenIndexedOperation)
    println(widened)
    println(widenedIndexed)

    val probe = ProbeIterable(listOf(1, 2, 3, 4))
    try {
        probe.reduce { acc: Int, value: Int ->
            if (value == 3) throw IllegalStateException("stop")
            acc + value
        }
        println("missing exception")
    } catch (e: IllegalStateException) {
        println("stopped")
    }
    println(probe.iteratorCalls)
    println(probe.iteratorValue.nextCalls)
}
