fun main() {
    val attempts = mutableListOf<String>()
    var shouldThrow = true
    val windows = "abcd".windowedSequence(2, 1, true) { chunk ->
        val value = chunk.toString()
        attempts.add(value)
        if (shouldThrow) {
            shouldThrow = false
            throw IllegalStateException("boom")
        }
        value + "!"
    }
    val iterator = windows.iterator()
    try {
        iterator.next()
        println("no throw")
    } catch (failure: IllegalStateException) {
        println("caught")
    }
    println(iterator.next())
    println(attempts)
}
