fun main() {
    val seq = sequenceOf(1, 2, 3, 4, 5)

    // Basic transform overloads, all arguments explicit.
    println(seq.chunked(2) { chunk -> chunk.sum() }.toList())
    println(seq.windowed(3, 1, false) { window -> window.sum() }.toList())

    // Trailing lambda with defaulted middle parameters skipped.
    println(seq.windowed(3) { window -> window.sum() }.toList())
    println(seq.windowed(2, 2) { window -> window.sum() }.toList())

    // Captured variable inside the transform lambda, with and without
    // defaulted middle parameters skipped.
    val bonus = 100
    println(seq.chunked(2) { chunk -> chunk.sum() + bonus }.toList())
    println(seq.windowed(3) { window -> window.sum() + bonus }.toList())
    println(seq.windowed(3, 1, false) { window -> window.sum() + bonus }.toList())

    // Empty receiver.
    println(emptySequence<Int>().chunked(2) { it.sum() }.toList())
    println(emptySequence<Int>().windowed(2) { it.sum() }.toList())

    // Validation still throws and is still catchable by the caller's
    // try/catch for the transform-taking overloads.
    try {
        seq.chunked(0) { it.sum() }.toList()
        println("no exception from chunked(0) transform")
    } catch (e: IllegalArgumentException) {
        println("chunked(0) transform: ${e.message}")
    }
    try {
        seq.windowed(0) { it.sum() }.toList()
        println("no exception from windowed(0) transform")
    } catch (e: IllegalArgumentException) {
        println("windowed(0) transform: ${e.message}")
    }
}
