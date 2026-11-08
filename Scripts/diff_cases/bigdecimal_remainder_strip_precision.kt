import java.math.BigDecimal

// KUU-4383: BigDecimal.remainder / stripTrailingZeros / precision parity.
fun main() {
    // remainder: sign follows dividend, integral quotient truncates toward zero.
    println(BigDecimal("10.5").remainder(BigDecimal("3")))
    println(BigDecimal("10.5").remainder(BigDecimal("-3")))
    println(BigDecimal("-10.5").remainder(BigDecimal("3")))
    println(BigDecimal("10.5").remainder(BigDecimal("4")))
    println(BigDecimal("7").remainder(BigDecimal("2")))
    println(BigDecimal("0").remainder(BigDecimal("5")))
    try {
        println(BigDecimal("1").remainder(BigDecimal("0")))
    } catch (e: ArithmeticException) {
        println("div0")
    }

    // stripTrailingZeros: scale may go negative; zero collapses to scale 0.
    println(BigDecimal("1.000").stripTrailingZeros())
    println(BigDecimal("1000").stripTrailingZeros())
    println(BigDecimal("600").stripTrailingZeros())
    println(BigDecimal("1.2300").stripTrailingZeros())
    println(BigDecimal("0.000").stripTrailingZeros())
    println(BigDecimal("0").stripTrailingZeros())
    println(BigDecimal("-100.50").stripTrailingZeros())
    println(BigDecimal("0.5").stripTrailingZeros())
    println(BigDecimal("-0.00").stripTrailingZeros())
    val stripped: BigDecimal = BigDecimal("12.3400").stripTrailingZeros()
    println("${stripped} scale=${stripped.scale()}")

    // precision: digit count of the unscaled value.
    println(BigDecimal("10.5").precision())
    println(BigDecimal("0.001").precision())
    println(BigDecimal("12300").precision())
    println(BigDecimal("0.00").precision())
    println(BigDecimal("-42.5").precision())
    println(BigDecimal("1E+3").precision())
    println(BigDecimal("123456789012345678901234567890.5").precision())
}
