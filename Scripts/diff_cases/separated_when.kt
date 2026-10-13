// KOTLINC_FLAGS: -Xjdk-release=17
sealed class ParseResult<out T>
abstract class Parsed<out T> : ParseResult<T>() { abstract val value: T }
class ParsedValue<out T>(override val value: T) : Parsed<T>()
class ErrorResult : ParseResult<Nothing>()
class Separated<T, S>(val terms: List<T>, val separators: List<S>)
fun <T, S> parse(first: ParseResult<T>, acceptZero: Boolean): ParseResult<Separated<T, S>> {
    val terms = mutableListOf<T>()
    val separators = mutableListOf<S>()
    return when (first) {
        is ErrorResult -> if (acceptZero) ParsedValue(Separated(emptyList(), emptyList())) else first
        is Parsed -> { terms.add(first.value); ParsedValue(Separated(terms, separators)) }
    }
}
fun main() {
    println(((parse<Int, String>(ErrorResult(), true) as Parsed<Separated<Int, String>>).value.terms).size)
    println(((parse<Int, String>(ParsedValue(7), false) as Parsed<Separated<Int, String>>).value.terms).size)
}
