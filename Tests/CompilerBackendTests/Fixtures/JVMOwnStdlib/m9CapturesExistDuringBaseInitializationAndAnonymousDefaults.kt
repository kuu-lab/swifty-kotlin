open class Base { init { println(value()) }; open fun value(): Int = 0 }
class Outer(private val x: Int) {
    open inner class Parent: Base() { override fun value(): Int = x }
    inner class Child: Parent()
    fun anonymous(): Base = object: Parent() { override fun value(): Int = x + 1 }
}
fun main() {
    val x = 42
    val a = object: Base() { override fun value(): Int = x }
    val b = object { fun result(n: Int = x): Int = n }
    println(b.result())
    val outer = Outer(20)
    outer.Child()
    outer.anonymous()
}
