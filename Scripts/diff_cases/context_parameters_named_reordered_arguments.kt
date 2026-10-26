import kotlin.ExperimentalContextParameters

@OptIn(ExperimentalContextParameters::class)
context(string: String, strings: List<String>)
fun test(x: Any, y: Int = 0): List<Any> = listOf(string, strings, x, y)

@OptIn(ExperimentalContextParameters::class)
fun main() {
    with("c1") { with(listOf("c2")) { println(test(y = 1, x = listOf(1))) } }
}
