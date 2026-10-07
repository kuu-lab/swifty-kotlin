// BUG-264: named (non-literal) object declarations must pass their
// superclass constructor arguments to the super <init> call. Before the fix
// the call was never emitted at all, so inherited properties kept their
// zeroed defaults (`Named.v` printed 0 instead of 7) and a no-arg
// superclass's own property initializers never ran either.

open class Base2(val v: Int)
object Named : Base2(7)

// No-arg header: the superclass's own property initializer only runs when
// the superclass constructor is actually invoked.
open class Fixed {
    val answer: Int = 42
    open fun describe(): String = "Fixed($answer)"
}
object NoArg : Fixed()

// Overload resolution: the super call must pick the constructor matching
// the object header's argument types, not just the first declared one.
open class Multi {
    val label: String
    constructor(v: Int) { label = "int:$v" }
    constructor(s: String) { label = "str:$s" }
}
object FromInt : Multi(7)
object FromString : Multi("hi")

// Super constructor arguments evaluate in the enclosing (top-level) scope.
val seed = 40
open class Seed(val s: Int)
object UsesTopLevel : Seed(seed + 2)

// The superclass constructor runs before the object's own initializers, so
// an inherited property set by `super(...)` is visible to them.
open class Step(val step: Int)
object Ordered : Step(3) {
    val own: Int = step * 10
}

// Overrides through a base-typed receiver keep dispatching to the object.
open class Base3 { open fun describe(): String = "base" }
object Named2 : Base3() { override fun describe(): String = "named" }

// Nested named objects with a class superclass: these never even got an
// initializer before (the gate only looked for interface supertypes), so
// inherited member reads panicked at runtime.
interface Iface { fun tag(): String }
class Outer {
    object N : Base2(9)
    object M : Base2(5), Iface { override fun tag(): String = "M" }
}

fun main() {
    println(Named.v)
    println(NoArg.answer)
    println(NoArg.describe())
    println(FromInt.label)
    println(FromString.label)
    println(UsesTopLevel.s)
    println(Ordered.own)
    val b: Base3 = Named2
    println(b.describe())
    println(Outer.N.v)
    println(Outer.M.v)
    println(Outer.M.tag())
    println(Outer.N is Base2)
    println(Outer.M is Iface)
}
