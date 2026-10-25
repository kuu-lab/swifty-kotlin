// Diagnostic cases for inner class constructors invoked through a class
// name qualifier (KSWIFTK-SEMA-0437). kotlinc rejects `Outer.I()`: an
// inner class constructor requires a receiver of the containing class.

open class Outer {
    inner class I
    inner class Inner { inner class Deep }
    fun mk() = I()            // OK: implicit this
    fun mkThis() = this.I()   // OK: explicit this receiver
}

class Outer2 { class Nested }
enum class E { A; inner class I }

// ERROR: class name does not provide an outer instance
class BareUse {
    val a = Outer.I()
    val b = Outer.Inner.Deep()
    val c = E.I()
}

// ERROR: local class name qualifiers are rejected the same way
fun localBad() {
    class L { inner class LI }
    L.LI()
}

// OK: instance receivers, nested classes, local class instances
fun main() {
    val o = Outer()
    o.I()
    Outer().I()
    Outer2.Nested()
    E.A.I()
    class LL { inner class LI2 }
    val l = LL()
    l.LI2()
    val t: Outer.I? = null
    t
}
