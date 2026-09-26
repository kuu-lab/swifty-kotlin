// Kotlin initializes `object` and `companion object` bodies lazily on first
// access (JVM `<clinit>` semantics), not eagerly at program start.

object Single {
    init { println("Single init") }
    val x = 7
}

class Comp {
    companion object {
        init { println("companion init") }
        val v = 42
    }
}

fun main() {
    println("start")
    println("before single")
    println(Single.x)
    println("after single")
    println("before comp")
    println(Comp.v)
    println("after comp")
}
