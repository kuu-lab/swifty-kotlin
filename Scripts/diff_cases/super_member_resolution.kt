open class Base { open fun f() = 1; fun classOnly() = 3 }
interface Default { fun f() = 2; fun interfaceOnly() = 4 }
class Qualified : Base(), Default {
    override fun f() = super<Base>.f() * 10 + super<Default>.f()
    fun distinct() = super.classOnly() * 10 + super.interfaceOnly()
}

open class Derived : Base()
interface DerivedDefault : Default
class Inherited : Derived(), DerivedDefault {
    override fun f() = super<Derived>.f() * 10 + super<DerivedDefault>.f()
}

interface Abstract { fun f(): Int }
class ConcreteClass : Base(), Abstract { override fun f() = super.f() + 10 }
abstract class AbstractClass { abstract fun f(): Int }
class ConcreteInterface : AbstractClass(), Default { override fun f() = super.f() + 20 }

open class Overloaded { fun f(x: Int) = x + 1; fun f(x: String) = x + "!" }
class Single : Overloaded() { fun g() = super.f(7); fun h() = super.f("ok") }

open class Generic<T> { open fun value(x: T): T = x }
class GenericChild : Generic<Int>() {
    override fun value(x: Int) = super.value(x)
    fun qualified(x: Int) = super<Generic>.value(x)
}

fun main() {
    println(Qualified().f())
    println(Qualified().distinct())
    println(Inherited().f())
    println(ConcreteClass().f())
    println(ConcreteInterface().f())
    println(Single().g())
    println(Single().h())
    println(GenericChild().value(42))
    println(GenericChild().qualified(43))
}
