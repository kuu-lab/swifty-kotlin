sealed class Shape {
    data class Circle(val radius: Int): Shape()
    object Empty: Shape()
}
fun area(shape: Shape): Int = when (shape) {
    is Shape.Circle -> shape.radius * 2
    Shape.Empty -> 0
}
sealed interface Outcome
object Done: Outcome
fun result(outcome: Outcome): Int = when (outcome) { Done -> 42 }
fun classify(value: Any?): Int = when (value) { is Int -> 1; is String? -> 2; else -> 3 }
fun main() {
    println(area(Shape.Circle(21)))
    println(area(Shape.Empty))
    println(Shape.Circle(2).copy(radius = 3))
    val shape: Shape? = null
    println(when (shape) { null -> 7; is Shape.Circle -> 8; Shape.Empty -> 9 })
    println(classify(42)); println(classify(null)); println(classify(false))
    println(result(Done))
}
