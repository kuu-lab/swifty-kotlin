fun interface Cmp<T> {
    fun compare(a: T, b: T): Int
}

fun applyAny(f: (Any) -> String): String = f(42)

fun main() {
    val c = Cmp { a: Int, b: Int -> a - b }
    println(c.compare(3, 1))

    val f = { a: Int, b: Int -> a - b }
    println(f(5, 2))

    val g: (String) -> Int = { s: String -> s.length }
    println(g("hello"))

    println(listOf(3, 1, 2).sortedBy { x: Int -> -x })

    // A declared `Any` parameter accepts an `Any` annotation and an unannotated
    // parameter alike; only narrowing it is rejected (BUG-163).
    val h: (Any) -> String = { v: Any -> "h=" + v.toString() }
    println(h(7))
    println(applyAny { v: Any -> "applyAny=" + v.toString() })
}
