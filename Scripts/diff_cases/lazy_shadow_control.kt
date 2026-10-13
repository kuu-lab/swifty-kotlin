open class Tokenizer
class DefaultTokenizer : Tokenizer()
abstract class Grammar<out T> {
    open val tokenizer: Tokenizer by lazy { DefaultTokenizer() }
}
class Demo : Grammar<Int>()
fun main() { println(Demo().tokenizer is DefaultTokenizer) }
