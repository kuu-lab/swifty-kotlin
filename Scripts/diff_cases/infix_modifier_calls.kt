// KUU-1313: valid infix calls and ordinary calls of non-infix functions.
open class InfixBase { open infix fun add(n: Int): Int = n }
class InfixChild : InfixBase() { override fun add(n: Int): Int = n + 1 }
class OrdinaryN(val v: Int) { fun add(n: Int): Int = v + n }
infix fun Int.join(other: Int): Int = this + other
fun main() {
    println(InfixChild() add 2)
    println(2 join 3)
    println(OrdinaryN(2).add(3))
    println(setOf(1).plus(2))
    println(1 and 3)
    println(1 to 2)
}
