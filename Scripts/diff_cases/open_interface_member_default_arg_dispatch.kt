interface Foo {
    fun bar(x: Int, y: Int = x + 1): Int
}
class FooImpl : Foo {
    override fun bar(x: Int, y: Int): Int = x + y
}

interface Greeter {
    fun greet(name: String, times: Int = 2): Int = name.length * times
}
class GreeterImpl : Greeter

open class Base {
    open fun baz(x: Int, y: Int = 100): Int = x + y
}
class Derived : Base() {
    override fun baz(x: Int, y: Int): Int = x - y
}

open class NoOverrideBase {
    open fun qux(x: Int, y: Int = 7): Int = x + y
}
class NoOverrideChild : NoOverrideBase()

abstract class AbstractBase {
    abstract fun compute(x: Int, y: Int = 3): Int
}
class AbstractImpl : AbstractBase() {
    override fun compute(x: Int, y: Int): Int = x * y
}

fun main() {
    val f: Foo = FooImpl()
    println(f.bar(10))

    val g: Greeter = GreeterImpl()
    println(g.greet("ab"))

    val d: Base = Derived()
    println(d.baz(5))

    val b: Base = Base()
    println(b.baz(5))

    val nc: NoOverrideBase = NoOverrideChild()
    println(nc.qux(1))

    val a: AbstractBase = AbstractImpl()
    println(a.compute(4))
}
