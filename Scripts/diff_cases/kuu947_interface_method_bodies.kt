// KUU-947: block-bodied interface methods must be executable defaults.
interface I {
    fun f(): Int { return 1 }
}

class C : I

class Override : I {
    override fun f(): Int = 7
}

interface Child : I {
    override fun f(): Int { return 3 }
}

open class Base : Child
class Derived : Base()

fun invoke(value: I): Int = value.f()

interface Operations {
    fun read(): Int
    fun compute(value: Int): Int { return read() + value }
    fun label(name: String): String { return "$name:${compute(1)}" }
}

class Implementation : Operations {
    override fun read(): Int = 40
}

fun main() {
    println(C().f())
    println(invoke(C()))
    println(invoke(Override()))
    println(Derived().f())
    println(invoke(Derived()))
    println(invoke(object : I {}))

    val operations: Operations = Implementation()
    println(operations.compute(2))
    println(operations.label("total"))
    println(Implementation().compute(3))
}
