fun interface Parser<out T> { fun parse(source: String): T }
class State {
    fun <T> Parser<T>.parse(): T = parse("")
}
fun <T> parser(block: State.() -> T): Parser<T> = Parser { block(State()) }
fun <T> combine(element: Parser<T>, separator: Parser<Unit>): Parser<T> {
    val wrapped = parser {
        separator.parse()
        element.parse()
    }
    return wrapped
}
fun main() {
    val element: Parser<Int> = Parser { 3 }
    val separator: Parser<Unit> = Parser { }
    println(combine(element, separator).parse(""))
}
