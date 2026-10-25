import java.math.BigDecimal

fun main() {
    println(BigDecimal("1.5"))
    println(BigDecimal(1.5))
    println(BigDecimal(0.1))
    println(BigDecimal(1.0))
    println(BigDecimal(-0.0))
    println(BigDecimal(1e20))
    try {
        BigDecimal(Double.NaN)
        println("missing non-finite error")
    } catch (_: NumberFormatException) {
        println("non-finite rejected")
    }
}
