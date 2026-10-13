// KUU-1932: a later inferred extension return must not contribute Any to a DSL vararg call.
class Parser<out T>(val value: T)
class ParserState(val choice: Int)

fun <T> parser(choice: Int, block: ParserState.() -> T): Parser<T> =
    Parser(ParserState(choice).block())

fun charParser(char: Char): Parser<Char> = Parser(char)
fun <T, R> Parser<T>.map(transform: (T) -> R): Parser<R> = Parser(transform(value))
fun <T> ParserState.any(vararg parsers: Parser<T>): T = any(parsers.toList())
fun <T> ParserState.any(list: List<Parser<T>>): T = list[choice].value
fun unicodeCharacter(): Parser<Char> = Parser('A')

fun specialCharacters(choice: Int): Parser<String> = parser(choice) {
    any(
        charParser('"').string(),
        charParser('b').map { "backspace" },
        unicodeCharacter().string()
    )
}

// Keep this declaration after its consumer to exercise forward return inference.
fun Parser<Char>.string() = map { it.toString() }

fun main() {
    println(specialCharacters(0).value)
    println(specialCharacters(1).value)
    println(specialCharacters(2).value)
}
