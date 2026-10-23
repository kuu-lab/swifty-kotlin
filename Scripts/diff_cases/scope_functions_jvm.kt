// DIFF_JVM

fun main() {
    println(5.let { it * 2 })
    println(5.run { this * 2 })
    println(run { 5 * 2 })
    println(StringBuilder().apply { append("x") })
    println(with("abc") { length })
}
