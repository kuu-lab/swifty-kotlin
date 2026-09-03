private class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        if (iteratorCalls > 1) throw IllegalStateException("iterator requested twice")
        return values.iterator()
    }
}

private class NullableComparator : Comparator<String?> {
    var calls: Int = 0
    var trace: String = ""

    override fun compare(first: String?, second: String?): Int {
        calls += 1
        trace += (first ?: "null")
        trace += "/"
        trace += (second ?: "null")
        trace += ";"
        return when {
            first == null && second == null -> 0
            first == null -> -1
            second == null -> 1
            first.length < second.length -> -1
            first.length > second.length -> 1
            else -> first.compareTo(second)
        }
    }
}

private class ThrowingComparator : Comparator<String> {
    override fun compare(first: String, second: String): Int {
        if (first == "error" || second == "error") throw IllegalStateException("comparator failed")
        return first.compareTo(second)
    }
}

fun main() {
    val nullable = OneShotIterable<String?>(listOf("bb1", null, "a", "bb2"))
    val comparator = NullableComparator()
    println(nullable.sortedWith(comparator))
    println(nullable.iteratorCalls)
    if (comparator.calls == 0 || comparator.trace.isEmpty()) {
        throw IllegalStateException("comparator was not called")
    }

    val comparatorFailure = OneShotIterable(listOf("ok", "error", "later"))
    try {
        comparatorFailure.sortedWith(ThrowingComparator())
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println(comparatorFailure.iteratorCalls)
}
