// KUU-2092: erased argument checks must precede the body and preserve valid calls.
open class Token(val n: Int)
class SubToken(n: Int) : Token(n)
abstract class Parent<T> { abstract fun accept(x: T) }
class Bounded<T : Token> : Parent<T>() {
    var calls = 0
    override fun accept(x: T) { calls++ }
}
class Chained<U : Token, T : U> : Parent<T>() {
    var calls = 0
    override fun accept(x: T) { calls++ }
}
class Unbounded<T> : Parent<T>() {
    var calls = 0
    override fun accept(x: T) { calls++ }
}
interface Sink<T> { fun accept(first: T, second: T) }
class NullableSink : Sink<Token?> {
    var calls = 0
    override fun accept(first: Token?, second: Token?) { calls++ }
}
class StringSink : Sink<String> {
    var text = ""
    override fun accept(first: String, second: String) { text = first + second }
}

fun main() {
    val bounded = Bounded<SubToken>()
    bounded.accept(SubToken(1))
    val erased = bounded as Parent<Any>
    // Check the erased Token bound, not the receiver's SubToken argument.
    erased.accept(Token(2))
    erased.accept(SubToken(3))
    try {
        erased.accept(Any())
        println("FAIL bounded")
    } catch (e: ClassCastException) { println("bounded CCE") }
    println(bounded.calls)

    val chained = Chained<Token, SubToken>()
    val erasedChained = chained as Parent<Any>
    erasedChained.accept(Token(4))
    try {
        erasedChained.accept(Any())
        println("FAIL chained")
    } catch (e: ClassCastException) { println("chained CCE") }
    println(chained.calls)

    val unbounded = Unbounded<Token>()
    (unbounded as Parent<Any?>).accept(Any())
    (unbounded as Parent<Any?>).accept(null)
    println(unbounded.calls)

    val nullable = NullableSink()
    val erasedNullable = nullable as Sink<Any?>
    erasedNullable.accept(null, Token(5))
    erasedNullable.accept(SubToken(6), null)
    try {
        erasedNullable.accept(Any(), null)
        println("FAIL first")
    } catch (e: ClassCastException) { println("first CCE") }
    try {
        erasedNullable.accept(null, Any())
        println("FAIL second")
    } catch (e: ClassCastException) { println("second CCE") }
    println(nullable.calls)

    val strings = StringSink()
    val erasedStrings = strings as Sink<Any>
    erasedStrings.accept("O", "K")
    try {
        erasedStrings.accept("bad", Any())
        println("FAIL string")
    } catch (e: ClassCastException) { println("string CCE") }
    println(strings.text)
}
