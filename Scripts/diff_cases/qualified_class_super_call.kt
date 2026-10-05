open class A1 { open fun f() = 1 }
interface B1 { fun f() = 2 }
class C1 : A1(), B1 {
    override fun f() = super<A1>.f() + super<B1>.f()
    fun classResult() = super<A1>.f()
    fun interfaceResult() = super<B1>.f()
}

open class Base(val offset: Int) {
    open fun add(x: Int) = offset + x
}
class Child : Base(7) {
    override fun add(x: Int) = super<Base>.add(x) + 10
    fun unqualified(x: Int) = super.add(x)
}

fun main() {
    val mixed = C1()
    println(mixed.f())
    println(mixed.classResult())
    println(mixed.interfaceResult())
    val child = Child()
    println(child.add(5))
    println(child.unqualified(5))
    val base: Base = child
    println(base.add(5))
}
