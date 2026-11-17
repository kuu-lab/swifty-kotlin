import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

fun showParts(label: String, value: BigDecimal, divisor: BigDecimal) {
    val parts = value.divideAndRemainder(divisor)
    println(label + " q=" + parts[0] + " qs=" + parts[0].scale() + " r=" + parts[1] + " rs=" + parts[1].scale())
}

fun main() {
    val negative = BigDecimal("-12.3400")
    println(negative.abs())
    println(negative.abs().scale())
    println(negative.negate())
    println(negative.negate().scale())
    println(BigDecimal("1.20E+3").toPlainString())
    println(BigDecimal("1.23E-7").toPlainString())
    println(BigDecimal("0E+1").toPlainString())
    println(BigDecimal("0.00").toPlainString())

    showParts("10.5/3", BigDecimal("10.5"), BigDecimal("3"))
    showParts("10.00/4", BigDecimal("10.00"), BigDecimal("4"))
    showParts("1.20E+3/3", BigDecimal("1.20E+3"), BigDecimal("3"))
    showParts("1.21E+3/3", BigDecimal("1.21E+3"), BigDecimal("3"))
    showParts("1.21E+3/30", BigDecimal("1.21E+3"), BigDecimal("30"))
    showParts("123.45/3.0", BigDecimal("123.45"), BigDecimal("3.0"))
    showParts("0.00/3", BigDecimal("0.00"), BigDecimal("3"))
    showParts("-10.5/3", BigDecimal("-10.5"), BigDecimal("3"))
    showParts("10.5/-3", BigDecimal("10.5"), BigDecimal("-3"))
    showParts("-10.5/-3", BigDecimal("-10.5"), BigDecimal("-3"))

    println(BigDecimal("1").divide(BigDecimal("3"), MathContext(2, RoundingMode.HALF_UP)))
    println(BigDecimal("2").divide(BigDecimal("3"), MathContext(2, RoundingMode.HALF_UP)))
    println(BigDecimal("999").divide(BigDecimal("10"), MathContext(2, RoundingMode.HALF_UP)))
    println(BigDecimal("1.23456").divide(BigDecimal.ONE, MathContext(3, RoundingMode.HALF_UP)))
    println(BigDecimal("1").divide(BigDecimal("8"), MathContext.UNLIMITED))
    println(BigDecimal("1").divide(BigDecimal("2"), MathContext(2, RoundingMode.HALF_UP)))
    println(BigDecimal("1.00").divide(BigDecimal("2"), MathContext(2, RoundingMode.HALF_UP)))
    println(BigDecimal("0.00").divide(BigDecimal("3"), MathContext(2, RoundingMode.HALF_UP)))
    try {
        println(BigDecimal("1").divide(BigDecimal("3"), MathContext.UNLIMITED))
    } catch (e: ArithmeticException) {
        println("nonterm")
    }
}
