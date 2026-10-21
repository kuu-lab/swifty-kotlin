fun main() {
    val x: Int? = null
    println(x.hashCode())
    println(x.toString())
    println(x == 5)
    println(x == null)
    val y: Int? = 5
    println(y.hashCode())
    println(y.toString())
    println(y == 5)
    val z: Long? = null
    println(z.hashCode())
    val c: Char? = null
    println(c.hashCode())
}
