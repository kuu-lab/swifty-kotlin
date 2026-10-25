// KUU-3400: primitive numeric conversions to BigDecimal.
import java.math.MathContext
import java.math.RoundingMode

fun main() {
    println(Int.MIN_VALUE.toBigDecimal())
    println(Int.MAX_VALUE.toBigDecimal())
    println(Long.MIN_VALUE.toBigDecimal())
    println(Long.MAX_VALUE.toBigDecimal())
    println(1.5.toBigDecimal())
    println(0.1.toBigDecimal())
    println(12345.toBigDecimal(MathContext(3, RoundingMode.HALF_UP)))
    println(12345L.toBigDecimal(MathContext(3, RoundingMode.DOWN)))
    println(1.235.toBigDecimal(MathContext(3, RoundingMode.HALF_EVEN)))
    println(999.toBigDecimal(MathContext(2, RoundingMode.HALF_UP)))
    println(0.1.toBigDecimal(MathContext.UNLIMITED))
}
