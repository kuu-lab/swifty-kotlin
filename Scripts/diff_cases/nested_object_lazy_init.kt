// BUG-274: a nested `object` (inside a class, not a companion) that inherits
// a class must still run its lazy clinit-equivalent -- including the
// implicit superclass constructor call -- before an *external*,
// further-qualified access to its state (`Outer.N.v`) reads it. This is a
// separate KIR-lowering path from a bare `object`/`companion` reference:
// `Outer.N` is resolved as a nested-type qualifier chain, not through the
// ordinary bare-name fallback.

open class Base(val v: Int)

class Outer {
    object N : Base(9) {
        init { println("N init") }
        val extra: Int = v + 1
    }
}

interface Tag { fun tag(): String }

class OuterWithIface {
    object M : Base(5), Tag {
        override fun tag(): String = "M"
    }
}

fun main() {
    println("start")
    println(Outer.N.v)
    println(Outer.N.extra)
    println(Outer.N is Base)
    println(OuterWithIface.M.v)
    println(OuterWithIface.M.tag())
    println(OuterWithIface.M is Tag)
}
