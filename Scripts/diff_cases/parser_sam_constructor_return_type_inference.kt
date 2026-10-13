package parser.base

fun interface Parser<out T> {
    fun parse(source: String): ParserResult<T>
}

sealed interface ParserResult<out T> {
    data class Success<out T>(val value: T, val remaining: String) : ParserResult<T>
    object Failure : ParserResult<Nothing> {
        override fun toString(): String = "Failure"
    }
}

fun main() {
    val intParser = Parser { _: String -> ParserResult.Success(3, "") }
    println(intParser.parse(""))

    val stringParser = Parser { _: String -> ParserResult.Success("ok", "") }
    println(stringParser.parse(""))

    val typedParser: Parser<Int> = Parser { _: String -> ParserResult.Success(3, "") }
    println(typedParser.parse(""))
}
