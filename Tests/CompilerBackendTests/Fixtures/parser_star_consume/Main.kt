import parser.base.*

fun main() {
    val original: Parser<Int> = Parser { source -> ParserResult.Success(3, source) }
    println(original.consume().parse("tail"))
}
