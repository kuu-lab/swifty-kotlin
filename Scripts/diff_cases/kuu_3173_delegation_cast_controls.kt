// KUU-3173 controls: plain delegation and a non-generic cast delegation keep
// working next to the generic-cast path, and a wrong-type erased generic
// delegate claim still throws a catchable ClassCastException at the claim
// site instead of silently returning null.
interface Printer {
    fun print(): String
}

class RealPrinter : Printer {
    override fun print() = "real"
}

class Holder(impl: Printer) : Printer by impl
class CastHolder(p: Printer) : Printer by (p as Printer)

interface Box<E> {
    fun get(): E
}

class C {
    override fun toString() = "C"
}

object ImplC : Box<C> {
    override fun get() = C()
}

class ParamBox<T>(b: Any) : Box<T> by (b as Box<T>)

class A {
    override fun toString() = "A"
}

class B

object ImplA : Box<A> {
    override fun get() = A()
}

class WrongBox<T> : Box<T> by (ImplA as Box<T>)

fun main() {
    println(Holder(RealPrinter()).print())
    println(CastHolder(RealPrinter()).print())
    println(ParamBox<C>(ImplC).get().toString())
    try {
        val b: B = WrongBox<B>().get()
        println("no cce: $b")
    } catch (cce: ClassCastException) {
        println("cce")
    }
}
