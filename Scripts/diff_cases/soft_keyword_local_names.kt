class Box<out T>(val v: T)

fun widen(xs: List<out Number>): Int = xs.size

fun main() {
    val out = 1
    println(out)

    var out2 = 10
    out2 = out2 + 5
    println(out2)

    fun out(): Int = 7
    println(out())

    val doubled = listOf(1, 2).map { n ->
        val out = n * 2
        out
    }
    println(doubled)

    println(Box(3).v)
    println(widen(listOf(1, 2, 3)))
}
