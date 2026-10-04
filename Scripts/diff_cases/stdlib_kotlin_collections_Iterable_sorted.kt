private class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        if (iteratorCalls > 1) throw IllegalStateException("iterator requested twice")
        return values.iterator()
    }
}

fun main() {
    val natural = OneShotIterable(listOf(3, 1, 2, 1))
    println(natural.sorted())
    println(natural.iteratorCalls)

    val descending = OneShotIterable(listOf(3, 1, 2, 1))
    println(descending.sortedDescending())
    println(descending.iteratorCalls)

    val by = OneShotIterable(listOf("b2", "a1", "b1", "a2"))
    var selectorCalls = 0
    println(by.sortedBy {
        selectorCalls += 1
        if (it == "a1" || it == "a2") null else 1
    })
    println(by.iteratorCalls)
    if (selectorCalls == 0) throw IllegalStateException("selector not called")

    println(OneShotIterable(emptyList<Int>()).sorted())
    println(OneShotIterable(listOf(7)).sortedDescending())

    val selectorFailure = OneShotIterable(listOf("ok", "boom", "later"))
    try {
        selectorFailure.sortedBy {
            if (it == "boom") throw IllegalStateException("selector failed")
            it
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println(selectorFailure.iteratorCalls)
}
