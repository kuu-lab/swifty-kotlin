// DIFF_JVM
// KUU-4000: Math.E is 2.718281828459045; 2.7182818284590455 is the next Double.
fun main() {
    println(Math.E)
    println(Math.E.toRawBits())
    println(Math.E == kotlin.math.E)
    println(Math.E.toRawBits() + 1L == 2.7182818284590455.toRawBits())

    val values = doubleArrayOf(
        Math.E,
        2.7182818284590455,
        -0.49999999999999983,
        0.10000000000000002,
        0.1 + 0.2,
        1.2345678901234567,
        1.2345678901234567e20,
        1.2345678901234567e-20,
        2.2250738585072014e-308,
        Double.MAX_VALUE,
        Double.MIN_VALUE,
        0.0,
        -0.0,
    )
    for (value in values) {
        val text = value.toString()
        val boxed: Any = value
        val nullable: Double? = value
        println(value)
        println(text)
        println("$value")
        println("value=" + value)
        println(boxed)
        println(nullable)
        println(text.toDouble().toRawBits() == value.toRawBits())
        println(boxed.toString() == text && nullable.toString() == text)
    }
}
