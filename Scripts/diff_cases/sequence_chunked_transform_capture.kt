fun main() {
    val s = sequenceOf(1, 2, 3, 4, 5)
    println(s.chunked(2) { it.sum() }.toList())
    println(s.chunked(2).toList())
    println(listOf(1, 2, 3, 4, 5).chunked(2) { it.sum() })

    val bonus = 100
    println(s.chunked(2) { it.sum() + bonus }.toList())
    val prefix = "chunk:"
    println(s.chunked(2) { prefix + it.joinToString("+") }.toList())
    println(s.chunked(2) { it.toList() }.toList())
    println(emptySequence<Int>().chunked(2) { it.sum() }.toList())

    // The callback escapes into both the sequence and its iterator.
    var calls = 0
    val chunks = s.chunked(2) {
        calls = calls + 1
        it.sum()
    }
    println(calls)
    println(chunks.take(1).toList())
    println(calls)
    println(chunks.toList())
    println(calls)

    try {
        s.chunked(2) { throw IllegalStateException("transform") }.toList()
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    try {
        s.chunked(0) { it.sum() }
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
