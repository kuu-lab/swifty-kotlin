// BUG-257: an `object` member property with a real custom getter has no
// backing global slot, so reading it must dispatch through the getter
// accessor function like an ordinary class-instance property read does --
// not through a `loadGlobal` of a slot that was never written. This covers
// the getter-only case, the getter+setter case (via an observable side
// effect in the setter), the implicit-receiver case (reading the property
// from another member of the same object, and from a `with` block), the
// companion object case (both via the class name and via an instance
// method's implicit receiver), and a guard that genuinely stored properties
// still take the plain storage path.
//
// A delegated object-member property (`by lazy { ... }`) and a `var`
// written through an implicit receiver are deliberately NOT covered here --
// both are separately broken and tracked as BUG-265.
object Foo {
    var log = ""
    val a: Int get() = 42
    var x: Int
        get() = 0
        set(value) { log += "set($value)" }

    fun viaImplicitReceiver() = a
}

class C {
    companion object {
        val a: Int get() = 1
    }

    fun viaCompanion() = a
}

object Stored {
    val s = 3
    var t = 4
}

fun main() {
    println(Foo.a)
    println(Foo.viaImplicitReceiver())
    Foo.x = 5
    println(Foo.log)
    println(Foo.x)
    println(C.a)
    println(C().viaCompanion())
    with(Foo) {
        println(a)
    }
    Stored.t = 9
    println("${Stored.s} ${Stored.t}")
}
