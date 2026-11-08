interface Named { fun label(): String }
data class P(val x: Int) : Named {
    override fun label() = "label$x"
    override fun toString() = "P(x=$x)"
}
data class Box(val v: String)
fun main() {
    val p = P(7)
    val c = p.copy()
    val a: Any = c
    println(a)
    println(a is P)
    println(a is Named)
    println((a as Named).label())
    println(a == P(7))
    println(c.toString())
    val b = Box("z").copy()
    println(b.toString())
    val anyB: Any = b
    println(anyB)
}
