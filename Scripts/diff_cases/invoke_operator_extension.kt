operator fun String.invoke(n: Int) = repeat(n)
operator fun Int.times(s: String) = s.repeat(this)
class Box(val v: Int)
operator fun Box.invoke(k: Int) = v * k
fun main() {
    println("xy"(2))
    println((2 * "a")(2))
    val s = "q"
    println(s(3))
    println(Box(5)(2))
}
