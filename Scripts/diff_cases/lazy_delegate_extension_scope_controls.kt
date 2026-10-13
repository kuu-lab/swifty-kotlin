import kotlin.reflect.KProperty

open class Tokenizer
class DefaultTokenizer : Tokenizer()
abstract class Grammar<out T> {
    open val tokenizer: Tokenizer by lazy { DefaultTokenizer() }
}
class Demo : Grammar<Int>()

open class MemberBase {
    protected operator fun Lazy<Int>.getValue(thisRef: MemberBase, property: KProperty<*>): Int = 41
}
class MemberGrammar : MemberBase() {
    val answer by lazy { 1 }
}

class ValueDelegate
operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 42
class LexicalGrammar {
    operator fun String.getValue(thisRef: LexicalGrammar, property: KProperty<*>): Int = 0
    val answer by ValueDelegate()
}
class WrongArgumentGrammar {
    operator fun ValueDelegate.getValue(thisRef: String, property: KProperty<*>): Int = 0
    val answer by ValueDelegate()
}
operator fun Lazy<Int>.getValue(thisRef: Any?, property: KProperty<*>): Int = 43
class LexicalLazyGrammar {
    val answer by lazy { 1 }
}

fun main() {
    println(Demo().tokenizer is DefaultTokenizer)
    println(MemberGrammar().answer)
    println(LexicalGrammar().answer)
    println(WrongArgumentGrammar().answer)
    println(LexicalLazyGrammar().answer)
}
