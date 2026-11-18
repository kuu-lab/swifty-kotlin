// KUU-4596: fill missing java.math.BigDecimal members used by JVM interop code.
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

fun show(label: String, value: BigDecimal) {
    println(
        "$label toString=${value} plain=${value.toPlainString()} " +
            "eng=${value.toEngineeringString()} scale=${value.scale()} " +
            "precision=${value.precision()} unscaled=${value.unscaledValue()}"
    )
}

fun showDivideToIntegral(label: String, dividend: BigDecimal, divisor: BigDecimal, context: MathContext) {
    try {
        show(label, dividend.divideToIntegralValue(divisor, context))
    } catch (e: ArithmeticException) {
        println("$label ArithmeticException: ${e.message}")
    }
}

fun main() {
    show("abs", BigDecimal("-5.00").abs())
    show("negate", BigDecimal("-5.00").negate())
    show("plus", BigDecimal("-5.00").plus())
    show("negate-negative-scale", BigDecimal("1E+3").negate())
    show("abs-negative-scale", BigDecimal("-1E+3").abs())
    show("negate-trailing-zeros", BigDecimal("1.2300E+5").negate())
    show("abs-trailing-zeros", BigDecimal("-1.2300E+5").abs())
    show("negate-zero-scale", BigDecimal("0.00").negate())
    show("negate-mc-negative-scale", BigDecimal("1E+3").negate(MathContext(2)))
    show("abs-mc-negative-scale", BigDecimal("-1E+3").abs(MathContext(1)))
    show("plain-large", BigDecimal("1.2300E+5"))
    show("plain-small", BigDecimal("1E-10"))
    show("plain-zero", BigDecimal("0E+3"))
    show("eng-large", BigDecimal("1E+10"))
    show("eng-ten", BigDecimal("1E+1"))
    show("eng-hundred", BigDecimal("1E+2"))
    show("eng-small", BigDecimal("1E-7"))
    show("eng-zero", BigDecimal("0E+1"))
    show("eng-zero-neg7", BigDecimal("0E-7"))
    show("eng-zero-neg8", BigDecimal("0E-8"))
    show("eng-zero-neg9", BigDecimal("0E-9"))
    show("eng-zero-neg10", BigDecimal("0E-10"))

    val boxed = arrayOf(BigDecimal("1.2"), BigDecimal("3.4"))
    println("array-box first=${boxed[0]} second=${boxed[1]} second-scale=${boxed[1].scale()}")

    val positive = BigDecimal("10.5").divideAndRemainder(BigDecimal("3"))
    println("divRem-positive q=${positive[0]}(${positive[0].scale()}) r=${positive[1]}(${positive[1].scale()})")
    val negativeDividend = BigDecimal("-10.5").divideAndRemainder(BigDecimal("3"))
    println("divRem-negative-dividend q=${negativeDividend[0]}(${negativeDividend[0].scale()}) r=${negativeDividend[1]}(${negativeDividend[1].scale()})")
    val negativeDivisor = BigDecimal("10.5").divideAndRemainder(BigDecimal("-3"))
    println("divRem-negative-divisor q=${negativeDivisor[0]}(${negativeDivisor[0].scale()}) r=${negativeDivisor[1]}(${negativeDivisor[1].scale()})")

    show("divToInt", BigDecimal("123.45").divideToIntegralValue(BigDecimal("1.2")))
    show("divToInt-negative-scale", BigDecimal("1").divideToIntegralValue(BigDecimal("1.00")))
    show("divToInt-positive-scale", BigDecimal("0.01").divideToIntegralValue(BigDecimal("0.001")))
    show("divToInt-mc", BigDecimal("123.45").divideToIntegralValue(BigDecimal("1.2"), MathContext(3)))
    show("divToInt-mc-scale-down", BigDecimal("120").divideToIntegralValue(BigDecimal.ONE, MathContext(2)))
    show("divToInt-mc-scale-down-thousand", BigDecimal("1000").divideToIntegralValue(BigDecimal.ONE, MathContext(2)))
    showDivideToIntegral("divToInt-mc-impossible", BigDecimal("123"), BigDecimal.ONE, MathContext(2))

    show("divide-mc-third", BigDecimal("1").divide(BigDecimal("3"), MathContext(3)))
    show("divide-mc-exact", BigDecimal("10").divide(BigDecimal("4"), MathContext(3)))
    show("divide-mc-carry", BigDecimal("9.99").divide(BigDecimal("1"), MathContext(2)))
    show("divide-mc-scale", BigDecimal("1.00").divide(BigDecimal("3"), MathContext(4)))
    show("divide-mc-rounding", BigDecimal("2.5").divide(BigDecimal("1"), MathContext(1, RoundingMode.HALF_DOWN)))

    show("round", BigDecimal("99.9").round(MathContext(2)))
    show("round-keep-zeros", BigDecimal("2.50").round(MathContext(3)))
    show("plus-mc", BigDecimal("9.99").plus(MathContext(2)))
    show("add-mc", BigDecimal("1.234").add(BigDecimal("2.345"), MathContext(4)))
    show("subtract-mc", BigDecimal("1.234").subtract(BigDecimal("2.345"), MathContext(4)))
    show("multiply-mc", BigDecimal("1.234").multiply(BigDecimal("2.345"), MathContext(4)))

    show("min", BigDecimal("1.0").min(BigDecimal("1.00")))
    show("max", BigDecimal("1.1").max(BigDecimal("1.01")))
    show("ulp", BigDecimal("1.23").ulp())
    show("ulp-negative-scale", BigDecimal("1E+3").ulp())
    show("ulp-zero-scale", BigDecimal("0.00").ulp())
    show("ulp-zero-negative-scale", BigDecimal("0E+3").ulp())

    println("intExact=${BigDecimal("1.0").intValueExact()}")
    println("longExact=${BigDecimal("123.0").longValueExact()}")
    println("shortExact=${BigDecimal("32767.0").shortValueExact()}")
    println("byteExact=${BigDecimal("127.0").byteValueExact()}")
}
