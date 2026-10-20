fun <T : Double> f(v: T) = v * v
fun <T : Double> g(v: T): Double = v * 1.0

fun main() {
    println(f(2.0))
    println(g(2.0))
}
