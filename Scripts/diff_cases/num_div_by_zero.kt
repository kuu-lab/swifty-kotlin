// PEC-NUM-0002: integer division/remainder by zero now throws ArithmeticException.
// Floating-point division by zero produces Infinity/NaN (IEEE 754).
fun main() {
    val n = 1
    val zero = 0
    try {
        println(n / zero)
    } catch (e: ArithmeticException) {
        println("int div: ArithmeticException")
    }
    try {
        println(n % zero)
    } catch (e: ArithmeticException) {
        println("int rem: ArithmeticException")
    }
    val d = 1.0
    val dz = 0.0
    println(d / dz)
    println((-d) / dz)
    println(dz / dz)
}
