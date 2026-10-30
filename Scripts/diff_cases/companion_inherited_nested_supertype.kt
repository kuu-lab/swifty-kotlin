// KUU-3128 / KT-54645: a companion object's superclass clause resolves
// nested classifiers inherited through the enclosing class's superclass
// chain. The bound edge makes the companion a subtype of the inherited
// nested classifier and inherits its members.
abstract class Base {
    open class Nested {
        fun tag() = "base"
    }
}

sealed class Derived : Base() {
    open class Nested {
        fun tag() = "derived"
    }
}

class Impl() : Derived() {
    companion object : Nested()
}

class Plain : Base() {
    companion object : Nested()
}

fun takeDerivedNested(x: Derived.Nested) = x.tag()
fun takeBaseNested(x: Base.Nested) = x.tag()

fun main() {
    println(takeDerivedNested(Impl))
    println(takeDerivedNested(Impl.Companion))
    val a: Derived.Nested = Impl
    val b: Derived.Nested = Impl.Companion
    println(a.tag() + b.tag())
    println(takeBaseNested(Plain))
    println(takeBaseNested(Plain.Companion))
    val c: Base.Nested = Plain
    val d: Base.Nested = Plain.Companion
    println(c.tag() + d.tag())
}
