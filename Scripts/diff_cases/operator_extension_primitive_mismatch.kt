data class Vec(val x: Int, val y: Int) { operator fun times(k: Int) = Vec(x * k, y * k) }
operator fun Int.times(v: Vec) = v * this
operator fun Int.times(s: String) = s.repeat(this)
operator fun Int.plus(s: String) = "$this+$s"
fun main() {
    val a = Vec(1, 2)
    println(3 * a)
    println(3 * "ab")
    println(2 + "x")
    println(3.times(a))
    println(3.times("ab"))
}
