private class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        if (iteratorCalls > 1) throw IllegalStateException("iterator requested twice")
        return values.iterator()
    }
}

fun main() {
    val byDescending = OneShotIterable(listOf("b2", "a1", "b1", "a2"))
    println(byDescending.sortedByDescending { if (it == "a1" || it == "a2") 0 else 1 })
    println(byDescending.iteratorCalls)
}
