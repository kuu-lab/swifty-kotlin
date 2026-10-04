fun t(x: Iterable<Int>) = "iter" + x.count()
fun sumAll(xs: Iterable<Int>): Int { var s = 0; for (x in xs) s += x; return s }

fun main() {
    println(t(1..3))
    println(t(listOf(1)))
    println(sumAll(1..4))
    println(sumAll(listOf(5, 6)))
    val it: Iterable<Int> = 1..3
    println(it.count())
    println(t(1 until 3))
    println(t(3 downTo 1))
    println(t(1..10 step 3))
}
