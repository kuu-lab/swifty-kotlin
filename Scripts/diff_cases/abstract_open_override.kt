abstract class Shape { abstract fun area(): Double; open fun describe() = "I am a shape" }
class Circle(val r: Double) : Shape() {
    override fun area() = 3.14159 * r * r
    override fun describe() = "Circle(r=$r)"
}
class Rect(val w: Double, val h: Double) : Shape() {
    override fun area() = w * h
}
fun main() {
    val shapes: List<Shape> = listOf(Circle(5.0), Rect(3.0, 4.0))
    for (s in shapes) { println("${s.describe()} area=${s.area()}") }
}
