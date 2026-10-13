// KOTLINC_FLAGS: -Xjdk-release=17
open class ParseResult<out T>
class ParsedValue<out T>(val value: T) : ParseResult<T>()
class Separated<T, S>(val terms: List<T>, val separators: List<S>)
fun <T, S> emptyResult(): ParseResult<Separated<T, S>> = ParsedValue(Separated(emptyList(), emptyList()))
fun main() {
    val result = emptyResult<Int, String>() as ParsedValue<Separated<Int, String>>
    println(result.value.terms.size)
    println(result.value.separators.size)
}
