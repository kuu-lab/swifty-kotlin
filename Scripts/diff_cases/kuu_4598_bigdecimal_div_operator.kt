import java.math.BigDecimal

// KUU-4598: BigDecimal `/` must divide with RoundingMode.HALF_EVEN at the
// dividend's scale (Kotlin/JVM semantics), not exact `divide(other)` which
// shifts the scale and throws ArithmeticException on non-terminating quotients.
fun main() {
    // Results keep the dividend scale and HALF_EVEN round the discarded digits.
    println(BigDecimal("10") / BigDecimal("4"))       // 2
    println(BigDecimal("2.25") / BigDecimal("1.5"))   // 1.50
    println(BigDecimal("1.00") / BigDecimal("2"))     // 0.50
    println(BigDecimal("7") / BigDecimal("2"))        // 4
    println(BigDecimal("5") / BigDecimal("2"))        // 2
    println(BigDecimal("10") / BigDecimal("8"))       // 1
    println(BigDecimal("10.00") / BigDecimal("8"))    // 1.25
    println(BigDecimal("2") / BigDecimal("0.5"))      // 4
    println(BigDecimal("1.234") / BigDecimal("1"))    // 1.234

    // Non-terminating quotients round at the dividend scale instead of throwing.
    println(BigDecimal("1") / BigDecimal("3"))        // 0
    println(BigDecimal("-1") / BigDecimal("3"))       // 0
    println(BigDecimal("1.00") / BigDecimal("3"))     // 0.33
    println(BigDecimal("2.00") / BigDecimal("3"))     // 0.67

    // divide(other) keeps exact-division semantics and still throws.
    try {
        BigDecimal("1").divide(BigDecimal("3"))
        println("missing division error")
    } catch (_: ArithmeticException) {
        println("non-terminating division rejected")
    }

    // Dividing by zero still throws.
    try {
        println(BigDecimal("1") / BigDecimal("0"))
    } catch (_: ArithmeticException) {
        println("division by zero rejected")
    }
}
