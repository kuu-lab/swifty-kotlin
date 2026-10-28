// JetBrains Kotlin testData/codegen/box/funInterface/typealiasedFunInterface.kt
fun interface Foo<A, B> { fun invoke(a: A): B }
typealias TA<K> = Foo<Int, K>
class Bar<X, Y>(val y: Y) { fun foo(x: X): Y = y }
typealias TB<M> = Bar<Int, M>

fun box(): String {
    val samResult = TA { "string" }.invoke(20)
    val constructorResult = TB("3").foo(3)
    return if (samResult == "string" && constructorResult == "3") "OK" else "FAIL"
}

fun main() {
    println(box())
}
