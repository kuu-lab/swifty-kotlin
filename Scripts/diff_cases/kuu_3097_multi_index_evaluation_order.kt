class Grid {
    operator fun get(a: Int, b: Int): Int = a * 10 + b
    operator fun set(a: Int, b: Int, v: Int) { println(a); println(b); println(v) }
}

fun main() {
    val g = Grid()
    var i = 0
    println(g[i, ++i])
    i = 0
    g[i, ++i] += 2
}
