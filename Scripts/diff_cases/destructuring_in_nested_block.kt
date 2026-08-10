// Destructuring declarations inside nested blocks (if / while / lambda bodies)
// go through the block-statement parser, which must recognise the `val (a, b)`
// pattern the same way top-level function bodies do. Extension `componentN`
// operators must also keep dispatching to the user declaration even when the
// name collides with a stdlib one.
class Box(val x: Int)

operator fun Box.component1(): Int = x

operator fun Box.component2(): Int = x + 1

data class Point(val x: Int, val y: Int)

fun main() {
    val pair = Pair(1, 2)
    if (pair.first > 0) {
        val (a, b) = pair
        println(a)
        println(b)
    }

    val triple = Triple(3, 4, 5)
    var count = 0
    while (count < 1) {
        val (r, s, t) = triple
        println(r)
        println(s)
        println(t)
        count++
    }

    val optional: Point? = Point(6, 7)
    if (optional != null) {
        val (px, py) = optional
        println(px)
        println(py)
    }

    val boxes = listOf(Box(8), Box(10))
    boxes.forEach { box ->
        val (first, second) = box
        println(first)
        println(second)
    }

    for (index in 0 until 1) {
        val (u, v) = Pair("u", "v")
        println(u)
        println(v)
    }
}
