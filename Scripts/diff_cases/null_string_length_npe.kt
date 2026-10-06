// BUG-B: an actually-null String must behave like any other null reference:
// `.length` throws NullPointerException (catchable), and string templates /
// `+` concatenation render it as the text "null", exactly like every other
// Kotlin reference type -- regardless of the statically-declared non-null
// type at the read site.

open class Base {
    open val name: String = "base"
    init {
        println("Base.init name=$name")
        try {
            println(name.length)
            println("no throw")
        } catch (e: NullPointerException) {
            println("caught NPE from length")
        }
        println("concat=" + (name + "!"))
    }
}

class Derived : Base() {
    override val name: String = "derived"
}

fun main() {
    val d = Derived()
    println(d.name)
    println(d.name.length)
}
