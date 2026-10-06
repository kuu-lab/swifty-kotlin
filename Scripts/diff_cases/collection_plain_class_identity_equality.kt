class P(val x: Int)

fun main() {
    val a = P(1)
    val b = P(1)
    println(setOf(a, b).size)
    println(b in listOf(a))
    println(a in listOf(a))
    println(listOf(a).indexOf(b))
    println(listOf(a) == listOf(b))
    println(listOf(a, b).distinct().size)
    println(mutableMapOf(a to "x")[b])
    println(mutableMapOf(a to "x")[a])
    println(a == b)
}
