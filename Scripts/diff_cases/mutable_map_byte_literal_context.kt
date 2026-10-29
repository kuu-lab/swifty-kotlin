// KUU-3688: An expected Pair value type contextualizes an infix-call literal.
fun main() {
    val mb = mutableMapOf<String, Byte>("k" to 127)
    println(mb["k"])
}
