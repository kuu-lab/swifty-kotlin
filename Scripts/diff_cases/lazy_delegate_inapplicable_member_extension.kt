import kotlin.reflect.KProperty
interface Parser<out T>
open class Tokenizer
class DefaultTokenizer : Tokenizer()
abstract class Grammar<out T> {
    protected operator fun <T> Parser<T>.provideDelegate(thisRef: Grammar<*>, property: KProperty<*>): Parser<T> = this
    protected operator fun <T> Parser<T>.getValue(thisRef: Grammar<*>, property: KProperty<*>): Parser<T> = this
    open val tokenizer: Tokenizer by lazy { DefaultTokenizer() }
}
class Demo : Grammar<Int>()
fun main() { println(Demo().tokenizer is DefaultTokenizer) }
