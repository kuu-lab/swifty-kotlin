import java.math.BigDecimal

// KUU-3997: BigDecimal.valueOf / BigDecimal.pow bundled API coverage.
fun main() {
    // valueOf(Double) follows Double.toString canonical semantics, unlike
    // the exact-binary BigDecimal(Double) constructor.
    println(BigDecimal.valueOf(2.0))
    println(BigDecimal.valueOf(0.1))
    println(BigDecimal.valueOf(1e10))
    println(BigDecimal.valueOf(-0.0))
    println(BigDecimal.valueOf(1.23456789012345E-4))
    println(BigDecimal.valueOf(Double.MIN_VALUE))
    println(BigDecimal.valueOf(Double.MAX_VALUE))
    println(BigDecimal.valueOf(1e22))
    try {
        BigDecimal.valueOf(Double.NaN)
        println("nan accepted")
    } catch (e: NumberFormatException) {
        println("nan rejected")
    }
    try {
        BigDecimal.valueOf(Double.POSITIVE_INFINITY)
        println("inf accepted")
    } catch (e: NumberFormatException) {
        println("inf rejected")
    }

    // valueOf(Long) and valueOf(Long, Int).
    println(BigDecimal.valueOf(123L))
    println(BigDecimal.valueOf(Long.MIN_VALUE))
    println(BigDecimal.valueOf(2))
    println(BigDecimal.valueOf(123, 2))
    println(BigDecimal.valueOf(123, -4))
    println(BigDecimal.valueOf(0, 5))
    println(BigDecimal.valueOf(-7, 0))

    // pow: exact exponentiation, result scale = this.scale() * n.
    println(BigDecimal("2").pow(10))
    println(BigDecimal("1.5").pow(4))
    println(BigDecimal("2.25").pow(3))
    println(BigDecimal("0.00").pow(5))
    println(BigDecimal("1E+3").pow(2))
    println(BigDecimal("9.99").pow(0))
    println(BigDecimal("0").pow(0))
    println(BigDecimal("-2").pow(3))
    println(BigDecimal("-2").pow(4))
    println(BigDecimal("1.20").pow(2).scale())
    try {
        BigDecimal("2").pow(-1)
        println("negative exponent accepted")
    } catch (e: ArithmeticException) {
        println("negative exponent rejected")
    }
    try {
        BigDecimal("2").pow(1000000000)
        println("huge exponent accepted")
    } catch (e: ArithmeticException) {
        println("huge exponent rejected")
    }
}
