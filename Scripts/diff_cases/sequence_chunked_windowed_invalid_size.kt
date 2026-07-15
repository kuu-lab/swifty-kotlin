fun main() {
    val seq = sequenceOf(1, 2, 3, 4, 5)

    try {
        seq.chunked(-1).toList()
        println("no exception from chunked(-1)")
    } catch (e: IllegalArgumentException) {
        println("chunked(-1): ${e.message}")
    }

    try {
        seq.chunked(0).toList()
        println("no exception from chunked(0)")
    } catch (e: IllegalArgumentException) {
        println("chunked(0): ${e.message}")
    }

    try {
        seq.windowed(-1).toList()
        println("no exception from windowed(-1)")
    } catch (e: IllegalArgumentException) {
        println("windowed(-1): ${e.message}")
    }

    try {
        seq.windowed(2, -1).toList()
        println("no exception from windowed(2, -1)")
    } catch (e: IllegalArgumentException) {
        println("windowed(2, -1): ${e.message}")
    }

    // Positive-path sanity check alongside the negative-path regression guard.
    println(seq.chunked(2).toList())
    println(seq.windowed(2).toList())
}
