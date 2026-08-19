class CovariantBox<out T>(val value: T) {
    fun accept(value: @UnsafeVariance T): T = value
}

fun main() {
    println(CovariantBox("stored").accept("accepted"))
}
