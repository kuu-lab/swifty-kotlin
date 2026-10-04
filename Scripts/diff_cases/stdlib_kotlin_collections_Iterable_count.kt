class TrackingIterator<T>(
    private val delegate: Iterator<T>,
    private val owner: TrackingIterable<T>
) : Iterator<T> {
    override fun hasNext(): Boolean = delegate.hasNext()

    override fun next(): T {
        owner.nextCalls += 1
        return delegate.next()
    }
}

class TrackingIterable<T>(private val source: List<T>) : Iterable<T> {
    var iteratorCalls = 0
    var nextCalls = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        return TrackingIterator(source.iterator(), this)
    }
}

class Counter {
    var value = 0
}

fun genericCount(values: Iterable<Int>): Int = values.count()

fun genericPredicate(values: Iterable<Int>, counter: Counter): Int = values.count {
    counter.value += 1
    true
}

fun main() {
    val custom = TrackingIterable(listOf(1, 2, 3, 4))
    println(custom.count())
    println(custom.iteratorCalls)
    println(custom.nextCalls)

    val evaluated = Counter()
    println(custom.count { value ->
        evaluated.value += 1
        value % 2 == 0
    })
    println(evaluated.value)
    println(custom.iteratorCalls)
    println(custom.nextCalls)

    val emptyEvaluated = Counter()
    println(genericPredicate(emptyList(), emptyEvaluated))
    println(emptyEvaluated.value)

    val nullable: Iterable<String?> = TrackingIterable(listOf(null, "x", null))
    println(nullable.count { it == null })

    println(genericCount(listOf(7, 8, 9)))
    val listEvaluated = Counter()
    println(genericPredicate(listOf(7, 8, 9), listEvaluated))
    println(listEvaluated.value)

    val exceptionEvaluated = Counter()
    try {
        TrackingIterable(listOf(1, 2, 3)).count {
            exceptionEvaluated.value += 1
            if (it == 2) throw IllegalStateException("stop")
            true
        }
    } catch (e: IllegalStateException) {
        if (e.message != "stop") error("unexpected exception message")
        println(exceptionEvaluated.value)
    }
}
