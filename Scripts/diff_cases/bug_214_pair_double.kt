// BUG-214: Double elements must survive Pair/Triple constructor bridges.
fun main() {
    val pair = Pair("x", 1.0)
    println(pair.second)

    val triple = Triple(1, "one", 1.0)
    println(triple.third)

    // Control: boxing Double directly and through a generic collection works.
    val boxed: Any = 1.0
    println(boxed)
    println(listOf<Any>(1, "s", 1.0))
}
