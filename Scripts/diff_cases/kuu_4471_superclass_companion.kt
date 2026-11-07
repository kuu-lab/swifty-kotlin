open class A {
    companion object {
        const val C = 10
        fun f(x: Int) = x + 1
    }
}
class B : A() {
    fun g(x: Int) = f(x) + C
}
open class Mid : A()
class Leaf : Mid() {
    fun h(x: Int) = f(x)
}
class Outer {
    class Inner2 : A() {
        class Deep { fun k(x: Int) = f(x) }
    }
}
class Shadowed : A() {
    companion object { fun f(x: Int) = x + 100 }
    fun s(x: Int) = f(x)
}

fun main() {
    println(B().g(1))
    println(Leaf().h(1))
    println(Outer.Inner2.Deep().k(1))
    println(Shadowed().s(1))
}
