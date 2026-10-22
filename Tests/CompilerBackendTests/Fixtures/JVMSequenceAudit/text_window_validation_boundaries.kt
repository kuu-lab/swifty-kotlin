fun main() {
    val text: CharSequence = "abcde"
    for (bounds in listOf(Pair(0, 0), Pair(0, 1), Pair(2, 0), Pair(-1, 2), Pair(2, -1), Pair(2, 2), Pair(2, 3))) {
        try { println(text.windowed(bounds.first, bounds.second, true)) } catch (failure: IllegalArgumentException) { println("window:" + failure.message) }
        try { println(text.windowed(bounds.first, bounds.second, true) { it.length }) } catch (failure: IllegalArgumentException) { println("transform:" + failure.message) }
    }
    var calls = 0
    try { text.chunked(-1) { calls++; it.length } } catch (failure: IllegalArgumentException) { println("chunk:" + failure.message) }
    println(calls)
}
