fun main() {
    for (length in listOf(-1, Int.MIN_VALUE, 0, 2, 3, 5)) {
        try { println("start:" + "abc".padStart(length, '*')) } catch (failure: IllegalArgumentException) { println("start:" + failure.message) }
        try { println("end:[" + "abc".padEnd(length) + "]") } catch (failure: IllegalArgumentException) { println("end:" + failure.message) }
    }
    try { println("".padStart(-3)) } catch (failure: IllegalArgumentException) { println("empty:" + failure.message) }
    println("".padEnd(0)); println("".padStart(2, '*'))
}
