fun main() {
    val seq = sequenceOf(1, 2, 3, 4, 5)

    try {
        seq.take(-1).toList()
        println("no exception from take(-1)")
    } catch (e: IllegalArgumentException) {
        println("take(-1): ${e.message}")
    }

    try {
        seq.drop(-1).toList()
        println("no exception from drop(-1)")
    } catch (e: IllegalArgumentException) {
        println("drop(-1): ${e.message}")
    }

    // Positive-path sanity check alongside the negative-path regression guard.
    println(seq.take(2).toList())
    println(seq.drop(2).toList())
}
