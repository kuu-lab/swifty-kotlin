// KUU-1930: preserve ParserResult and both generic map extensions.
sealed interface ParserResult<out T> {
    data class Success<out T>(val value: T, val remaining: String) : ParserResult<T>
    object Failure : ParserResult<Nothing> {
        override fun toString(): String = "Failure"
    }
}
fun interface Parser<out T> {
    fun parse(source: String): ParserResult<T>
}
inline fun <T, R> ParserResult<T>.map(transform: (T) -> R): ParserResult<R> =
    when (this) {
        ParserResult.Failure -> ParserResult.Failure
        is ParserResult.Success -> ParserResult.Success(transform(value), remaining)
    }
inline fun <T, R> Parser<T>.map(crossinline transform: (T) -> R): Parser<R> = Parser { source ->
    val result = parse(source)
    result.map(transform)
}
typealias Consumer = Parser<Unit>
fun Parser<*>.consume(): Consumer = map { }
fun main() {
    val original: Parser<Int> = Parser { source -> ParserResult.Success(3, source) }
    println(original.consume().parse("tail"))
}
