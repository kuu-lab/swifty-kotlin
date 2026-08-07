fun interface Cmp<T> {
    fun compare(a: T, b: T): Int
}

fun main() {
    val c = Cmp { a: Int, b: Int -> a - b }
    println(c.compare(3, 1))

    val f = { a: Int, b: Int -> a - b }
    println(f(5, 2))

    val g: (String) -> Int = { s: String -> s.length }
    println(g("hello"))

    println(listOf(3, 1, 2).sortedBy { x: Int -> -x })
}
