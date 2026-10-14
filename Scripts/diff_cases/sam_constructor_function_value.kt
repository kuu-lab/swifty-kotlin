// KUU-2164: an explicit SAM constructor accepts a variable of function type,
// not only a lambda literal or callable reference.
fun interface Stringify {
    fun render(value: Int): String
}

fun main() {
    val f: (Int) -> String = { "v=$it" }
    println(Stringify(f).render(42))

    val cmp: (Int, Int) -> Int = { a, b -> a - b }
    val comparator = Comparator<Int>(cmp)
    println(comparator.compare(3, 5))
    println(listOf(4, 2, 9).sortedWith(comparator))
}
