data class Point(val x: Int, var label: String) { var ignored = 0 }
data class Box<T>(val value: T)
data class Samples(val value: Double, val flags: IntArray)
data class Number(val value: Double)
data class Custom(val value: Int) { override fun toString(): String = "custom"; override fun hashCode(): Int = 7 }
fun main() {
    val first = Point(21, "left")
    println(first)
    println(first.component1())
    println(first.copy(x = 42))
    println(first.copy())
    val other = Point(21, "left")
    other.ignored = 9
    println(first == other)
    println(first.hashCode() == other.hashCode())
    val (x, label) = first
    println(x); println(label)
    println(Box("generic").copy().value)
    val array = intArrayOf(1, 2)
    println(Samples(0.5, array))
    println(Samples(0.5, array) == Samples(0.5, array))
    println(Samples(0.5, array) == Samples(0.5, intArrayOf(1, 2)))
    val nan = 0.0 / 0.0
    println(Number(nan) == Number(nan))
    println(Number(-0.0) == Number(0.0))
    println(Custom(1).copy())
    println(Custom(1).hashCode())
}
