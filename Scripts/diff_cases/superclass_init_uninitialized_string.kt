// An overridden `String` property read during the superclass constructor
// observes the subclass's not-yet-initialized backing field, which is null:
// string templates render it as "null" and `.length` throws NPE.

open class Base {
    open val name: String = "base"
    init { println("Base.init name=$name") }
}

class Derived : Base() {
    override val name: String = "derived"
}

fun main() {
    val d = Derived()
    println(d.name)
}
