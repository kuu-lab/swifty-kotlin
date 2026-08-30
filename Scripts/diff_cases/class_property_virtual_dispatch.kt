// BUG-227: an open/abstract/override *class* property (stored, custom-getter,
// or custom-setter) read or written through a base-typed reference must
// dispatch to the actual runtime type's accessor, exactly like an ordinary
// open/override method already does. Before the fix, every access resolved
// the accessor purely from the receiver's static type, so a base-typed
// reference always observed the base declaration's own storage — basic
// class inheritance polymorphism was broken for properties.
open class Base {
    open val p = "bp"
    open fun f() = "base"
}

class Derived : Base() {
    override val p = "dp"
    override fun f() = "derived"
}

open class GetterBase {
    open val p: String get() = "bp"
}

class GetterDerived : GetterBase() {
    override val p: String get() = "dp"
}

open class SetterBase {
    open var p: String = "base-init"
        set(value) { field = "base:" + value }
}

class SetterDerived : SetterBase() {
    override var p: String = "derived-init"
        set(value) { field = "derived:" + value }
}

abstract class Shape {
    abstract val area: Double
}

class Square(val side: Double) : Shape() {
    override val area: Double get() = side * side
}

fun main() {
    val b: Base = Derived()
    println(b.p)
    println(b.f())

    val g: GetterBase = GetterDerived()
    println(g.p)

    val s: SetterBase = SetterDerived()
    s.p = "x"
    println(s.p)

    val shape: Shape = Square(3.0)
    println(shape.area)
}
