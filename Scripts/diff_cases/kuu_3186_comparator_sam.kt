// DIFF_JVM
fun describe(c: Comparator<Int>, a: Int, b: Int) = c.compare(a, b)

fun main() {
    val c = Comparator<Int> { a, b -> b - a }
    println(describe(c, 1, 2))
    println(describe(c, 2, 1))
    println(describe(c, 5, 5))
    val byLength: Comparator<String> = Comparator { a, b -> a.length - b.length }
    println(byLength.compare("ab", "abc"))
    println(byLength.compare("abc", "a"))
}
