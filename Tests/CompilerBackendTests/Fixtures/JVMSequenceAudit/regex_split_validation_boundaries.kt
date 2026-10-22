fun main() {
    val pattern = Regex(",")
    val input: CharSequence = StringBuilder("a,b,")
    for (limit in listOf(-2, -1, 0, 1, 2)) {
        try { println(pattern.split(input, limit)) } catch (failure: IllegalArgumentException) { println("split:" + failure.message) }
        try { println(pattern.splitToSequence(input, limit).toList()) } catch (failure: IllegalArgumentException) { println("sequence:" + failure.message) }
    }
}
