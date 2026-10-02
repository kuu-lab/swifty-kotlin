class Top(val n: Int)

fun mk(n: Int): Top = Top(n)

fun label(n: Int): String = "n=" + n

class Outer {
    class Nested(val s: String)
    inner class Inner(val k: Int)
}

fun main() {
    // Function reference returning a class type
    val a = listOf(1, 2).map(::mk)
    println(a[0].n + a[1].n)
    val b: List<Top> = listOf(3, 4).map(::mk)
    println(b.size)

    // Constructor reference
    val c = listOf(5, 6).map(::Top)
    println(c[1].n)

    // Function reference returning String keeps member access on the result
    val d = listOf(7, 8).map(::label)
    println(d[0].length)

    // Nested class constructor reference
    val e = listOf("x", "y").map(Outer::Nested)
    println(e[1].s)

    // mapNotNull with a class-returning reference
    val f = listOf(1, 2).mapNotNull(::mk)
    println(f[1].n)
}
