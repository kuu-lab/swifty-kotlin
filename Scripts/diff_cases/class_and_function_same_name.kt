class Point(val x: Int, val y: Int)

fun Point(value: Int): Point = Point(value, value)

fun Point(pair: Pair<Int, Int>): Point = Point(pair.first, pair.second)

fun main() {
    val a = Point(3, 4)
    val b = Point(5)
    val c = Point(1 to 2)
    println("${a.x},${a.y}")
    println("${b.x},${b.y}")
    println("${c.x},${c.y}")
}
