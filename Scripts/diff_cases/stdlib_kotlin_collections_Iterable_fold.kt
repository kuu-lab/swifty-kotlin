class OneShot<T>(private val values: List<T>) : Iterable<T> {
    private var used = false
    var iteratorCalls = 0

    override fun iterator(): Iterator<T> {
        if (used) throw IllegalStateException("iterator reused")
        used = true
        iteratorCalls += 1
        return values.iterator()
    }
}

fun main() {
    val emptyFold: Iterable<Int> = OneShot(emptyList())
    println(emptyFold.fold(123) { acc, value -> acc + value })
    val emptyFoldIndexed: Iterable<Int> = OneShot(emptyList())
    println(emptyFoldIndexed.foldIndexed("initial") { index, acc, value -> "$acc$index:$value" })

    val ordered = OneShot(listOf(1, 2, 3))
    println(ordered.fold(0) { acc, value -> acc * 10 + value })
    println("fold-iterators=${ordered.iteratorCalls}")

    val indexed = OneShot(listOf(4, 5, 6))
    println(indexed.foldIndexed("") { index, acc, value -> "$acc$index:$value;" })
    println("foldIndexed-iterators=${indexed.iteratorCalls}")

    val nullableElements: Iterable<String?> = OneShot(listOf(null, "x", null))
    val nullableInitial: String? = null
    println(nullableElements.fold(nullableInitial) { acc, value -> (acc ?: "start") + (value ?: "null") })

    val differentTypes: Iterable<Char> = OneShot(listOf('a', 'b'))
    println(differentTypes.fold(0) { acc, value -> acc + value.toString().length })

    var visited = ""
    try {
        OneShot(listOf(1, 2, 3)).fold(0) { acc, value ->
            visited += value.toString()
            if (value == 2) throw IllegalStateException("fold stop")
            acc + value
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println("fold-visited=$visited")

    var indexedVisited = ""
    try {
        OneShot(listOf(7, 8, 9)).foldIndexed(0) { index, acc, value ->
            indexedVisited += "$index:$value;"
            if (value == 8) throw IllegalStateException("foldIndexed stop")
            acc + value
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println("foldIndexed-visited=$indexedVisited")
}
