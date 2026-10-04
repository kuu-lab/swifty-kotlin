// Writing a `var` through an interface-typed receiver had no dispatch path
// at all (the getter side has itable dispatch; the setter side fell through
// to an undefined-symbol call). Covers a directly implementing class, a
// polymorphic override chain, an interface implemented transitively through
// an empty pass-through interface, and an object literal.
interface Holder {
    var value: Int
    val readOnly: Int
}

open class Base : Holder {
    override var value: Int = 1
    override val readOnly: Int = 100
}

class Sub : Base() {
    override var value: Int = 2
}

class Other : Holder {
    override var value: Int = 10
    override val readOnly: Int = 200
}

interface Grand : Holder

class GrandImpl : Grand {
    override var value: Int = 5
    override val readOnly: Int = 500
}

fun writeThrough(h: Holder, v: Int) {
    h.value = v
}

fun main() {
    val h: Holder = Base()
    println(h.value)
    h.value = 99
    println(h.value)

    val impls: List<Holder> = listOf(Base(), Sub(), Other(), GrandImpl())
    for (holder in impls) {
        writeThrough(holder, holder.value + 1000)
        println("${holder.value} ${holder.readOnly}")
    }

    val obj: Holder = object : Holder {
        override var value: Int = 7
        override val readOnly: Int = 700
    }
    obj.value = 77
    println("${obj.value} ${obj.readOnly}")
}
