import java.math.BigDecimal
import java.math.RoundingMode

fun main() {
    println(BigDecimal("1.5") + BigDecimal("2.5"))
    println(BigDecimal("1.20").add(BigDecimal("2.3")))
    println(BigDecimal("5.00") - BigDecimal("7"))
    println(BigDecimal("1.20") * BigDecimal("2.0"))
    println(BigDecimal("1").divide(BigDecimal("8")))
    println(BigDecimal("1").divide(BigDecimal("3"), 2, RoundingMode.HALF_UP))
    println(BigDecimal("1.00").divide(BigDecimal("3"), RoundingMode.DOWN))
    println(BigDecimal("1.00").divide(BigDecimal("3"), 1))
    println(BigDecimal("1.245").setScale(2, RoundingMode.HALF_UP))
    println(BigDecimal("1.245").setScale(2, RoundingMode.HALF_DOWN))
    println(BigDecimal("1.245").setScale(2, RoundingMode.HALF_EVEN))
    println(BigDecimal("-1.241").setScale(2, RoundingMode.CEILING))
    println(BigDecimal("-1.241").setScale(2, RoundingMode.FLOOR))
    println(BigDecimal("1000").setScale(-1, RoundingMode.UNNECESSARY))
    println(BigDecimal("1.234").setScale(2, 1))
    try {
        BigDecimal("1").divide(BigDecimal("3"))
        println("missing division error")
    } catch (_: ArithmeticException) {
        println("non-terminating division rejected")
    }
    try {
        BigDecimal("1.234").setScale(2, RoundingMode.UNNECESSARY)
        println("missing rounding error")
    } catch (_: ArithmeticException) {
        println("unnecessary rounding rejected")
    }
}
