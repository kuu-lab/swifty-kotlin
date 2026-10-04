class Box(val n: Int)

fun main() {
    val b = Box(1)
    b.n += 5
    println(b.n)
}
