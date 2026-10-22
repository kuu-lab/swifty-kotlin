var evaluations = 0
fun defaults(): Array<String> { evaluations++; return arrayOf("default") }
fun count(vararg xs: String = defaults()): Int = xs.size
fun plain(vararg xs: String): Int = xs.size
fun numbers(vararg xs: Int = intArrayOf(1, 2)): Int = xs.size
fun main() {
    val f: () -> Int = ::count
    println(evaluations)
    println(f()); println(evaluations)
    println(f()); println(evaluations)
    val empty: () -> Int = ::plain
    println(empty())
    val packed: (Array<String>) -> Int = ::count
    println(packed(arrayOf("x", "y"))); println(evaluations)
    val numeric: () -> Int = ::numbers
    println(numeric())
}
