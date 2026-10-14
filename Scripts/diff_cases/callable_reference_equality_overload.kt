fun f(value: Int): Int = 0
fun f(value: String): String = ""
fun g(value: Int): Int = 0

fun captureInt(function: (Int) -> Int): (Int) -> Int = function

fun main() {
    val first = captureInt(::f)
    val second = captureInt(::f)
    println(first == second)
    println(first.hashCode() == second.hashCode())
    println(first == captureInt(::g))
}
