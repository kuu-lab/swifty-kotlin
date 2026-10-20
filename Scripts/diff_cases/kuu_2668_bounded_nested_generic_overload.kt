// KUU-2668: an inapplicable Int overload must not discard the String candidate's contextual inference.
fun <T : String> value(): T = "x" as T
fun choose(value: String): String = value
fun choose(value: Int): String = "int"

fun main() {
    val actual: String = choose(value())
    println(actual)
}
