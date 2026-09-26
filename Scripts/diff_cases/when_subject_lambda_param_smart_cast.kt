sealed interface Shape
class Circle(val r: Double) : Shape
class Rect(val w: Double, val h: Double) : Shape

fun main() {
    val shapes: List<Shape> = listOf(Circle(1.0), Rect(2.0, 3.0))
    println(shapes.map { when (it) { is Circle -> "c${it.r}"; is Rect -> "r${it.w}x${it.h}" } })
    println(shapes.map { s -> when (s) { is Circle -> "c${s.r}"; is Rect -> "r${s.w}x${s.h}" } })
    println(shapes.map { if (it is Circle) "c${it.r}" else "other" })
    val anys: List<Any> = listOf(1, "ab")
    println(anys.map { when (it) { is Int -> it + 1; is String -> it.length; else -> 0 } })
}
