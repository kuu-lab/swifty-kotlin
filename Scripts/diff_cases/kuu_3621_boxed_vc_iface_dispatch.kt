// KUU-3621: a value class boxed to its interface type must dispatch
// compareTo to the user's override — including when receiver and argument
// are the same handle — rather than falling back to the primitive
// identity/payload comparison inside the runtime bridge.

@JvmInline
value class Foo(val x: Int) : Comparable<Foo> {
    override fun compareTo(other: Foo): Int = 10
    override fun toString(): String = "FOO($x)"
}

interface Greeter {
    fun greet(): String
}

@JvmInline
value class Name(val s: String) : Greeter {
    override fun greet(): String = "hi $s"
}

fun main() {
    val f1 = Foo(42)
    val f2 = Foo(42)
    val f3 = Foo(7)
    val ff1: Comparable<Foo> = f1
    println(ff1.compareTo(f1))
    println(ff1.compareTo(f2))
    println(ff1.compareTo(f3))
    println(f1.compareTo(f1))
    println(f1.compareTo(f3))

    val g: Greeter = Name("a")
    println(g.greet())

    val a1: Any = f1
    println(a1.toString())
    println("$a1")
    println(a1.hashCode() == f1.hashCode())

    println(compareValues(f1, f1))
    println(compareValues(f1, f3))
}
