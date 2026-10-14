fun main() {
    val f = l@ fun(x: Int): Int {
        if (x > 1) return@l x * 2
        return 0
    }
    println(f(3))
    println(f(1))
    val g = m@ fun(): String = "ok"
    println(g())
}
