import kotlin.text.CASE_INSENSITIVE_ORDER

fun main() {
    val a = CASE_INSENSITIVE_ORDER
    val b = CASE_INSENSITIVE_ORDER
    println(a === b)
    println(CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA"))
    println(listOf("b", "A", "c", "a").sortedWith(CASE_INSENSITIVE_ORDER))
}
