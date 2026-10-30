// Indexed access/assignment on projected receivers must apply use-site
// variance: `out` forbids writes, `in` reads the captured upper bound.
// The rejected shapes are covered by Sema tests; this case exercises the
// accepted matrix.
fun main() {
    val outList: MutableList<out Int> = mutableListOf(7, 8)
    val x: Int = outList[0]
    println(x)
    val inList: MutableList<in Int> = mutableListOf(1, 2)
    inList[0] = 9
    val y: Any? = inList[0]
    println(y)
    val star: MutableList<*> = mutableListOf("a")
    val s: Any? = star[0]
    println(s)
    val ints: MutableList<Int> = mutableListOf(3)
    ints[0] += 4
    println(ints[0])
    println(outList[1])
}
