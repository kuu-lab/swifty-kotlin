open class Base {
    override fun toString(): String = "base"
}

open class Child : Base() {
    override fun toString(): String = "child"
}

class Leaf : Child() {
    override fun toString(): String = "leaf"
}

open class Plain

class PlainChild : Plain()

fun describe(b: Base): String = b.toString()

fun main() {
    val b: Base = Child()
    println(b.toString())
    println(Child().toString())
    println(Base().toString())
    println(describe(Leaf()))
    println(describe(Base()))

    val p: Plain = PlainChild()
    println(p.toString().isNotEmpty())
    println(Plain().toString().isNotEmpty())
}
