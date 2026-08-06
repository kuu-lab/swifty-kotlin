class Pair3(val a: String, val b: String, val c: String) {
    operator fun component1(): String = a
    operator fun component2(): String = b
    operator fun component3(): String = c
}

fun main() {
    // Destructuring inside a nested block
    if (true) {
        val (x, y, z) = Pair3("1", "2", "3")
        println(x)
        println(y)
        println(z)
    }

    // Destructuring a smart-cast nullable receiver
    val maybe: Pair3? = Pair3("a", "b", "c")
    if (maybe != null) {
        val (p, _, r) = maybe
        println(p)
        println(r)
    }

    // Nested loop body
    for (i in 0 until 2) {
        val (u, v) = Pair3("u$i", "v$i", "w$i")
        println(u)
        println(v)
    }
}
