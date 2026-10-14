package reflectionsingleton

object Token
object DirectFirst
private object Hidden
interface Marker
class Holder {
    // Nested singleton allocation without supertypes is covered by merged PR #8931 (KUU-2042).
    object Nested : Marker
    companion object Named
}
class Ordinary

fun classifier(value: Any) = value::class
fun hiddenClassifier() = classifier(Hidden)
fun hiddenDirect(): kotlin.reflect.KClass<*> = Hidden::class

fun main() {
    // Read names before evaluating a direct literal for the same classifier.
    val dynamic = classifier(Token)
    println(dynamic.simpleName)
    println(dynamic.qualifiedName)
    println(dynamic == Token::class)
    println(dynamic == Token::class)
    println(classifier(Token) == dynamic)
    println(Token::class.simpleName)
    println(Token::class.qualifiedName)

    val direct = DirectFirst::class
    println(classifier(DirectFirst) == direct)
    println(classifier(DirectFirst).simpleName)
    println(classifier(DirectFirst).qualifiedName)

    val hidden = hiddenClassifier()
    println(hidden.simpleName)
    println(hidden.qualifiedName)
    println(hidden == hiddenDirect())

    val nested = classifier(Holder.Nested)
    println(nested.simpleName)
    println(nested.qualifiedName)
    println(nested == Holder.Nested::class)

    val companion = classifier(Holder.Named)
    println(companion.simpleName)
    println(companion.qualifiedName)
    println(companion == Holder.Named::class)

    val ordinary = classifier(Ordinary())
    println(ordinary.simpleName)
    println(ordinary.qualifiedName)
    println(ordinary == Ordinary::class)
    println(classifier("text") == String::class)
    println(classifier(7) == Int::class)
    println(dynamic == ordinary)
}
