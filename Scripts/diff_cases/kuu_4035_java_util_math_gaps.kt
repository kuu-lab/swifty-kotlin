import java.math.BigDecimal
import java.util.Calendar
import java.util.Currency
import java.util.Date
import java.util.GregorianCalendar

fun main() {
    println(BigDecimal.TEN)
    println(BigDecimal.TEN.scale())
    println(BigDecimal("1.234").unscaledValue())
    println(BigDecimal("-12.34").unscaledValue())
    println(BigDecimal("1.234E+7").unscaledValue())
    println(BigDecimal("0.001").unscaledValue())
    println(BigDecimal("0.00").unscaledValue())
    println(BigDecimal.TEN.unscaledValue())
    println(BigDecimal("123.4500").unscaledValue())
    println(BigDecimal("1.234").movePointRight(2))
    println(BigDecimal("1234").movePointLeft(3))
    println(BigDecimal("-0.5").signum())
    println(BigDecimal("123.99").toBigInteger())
    try {
        BigDecimal("1.5").toBigIntegerExact()
        println("missing exactness error")
    } catch (_: ArithmeticException) {
        println("inexact conversion rejected")
    }
    println(BigDecimal("100").toBigIntegerExact())

    val cal = GregorianCalendar(2024, 0, 15)
    println(cal.get(Calendar.YEAR))
    println(cal.get(Calendar.MONTH))
    println(cal.get(Calendar.DAY_OF_MONTH))
    println(cal.get(Calendar.HOUR_OF_DAY))
    println(cal.get(Calendar.MINUTE))
    println(cal.get(Calendar.SECOND))
    println(cal.get(Calendar.MILLISECOND))
    println(cal.timeInMillis > 0L)

    val withTime = GregorianCalendar(2024, 0, 15, 10, 30)
    println(withTime.get(Calendar.HOUR_OF_DAY))
    println(withTime.get(Calendar.MINUTE))
    println(withTime.get(Calendar.SECOND))
    val withSeconds = GregorianCalendar(2024, 0, 15, 10, 30, 45)
    println(withSeconds.get(Calendar.SECOND))

    // Lenient field overflow, matching java.util.Calendar semantics.
    val lenient = GregorianCalendar(2024, 1, 30)
    println(lenient.get(Calendar.YEAR))
    println(lenient.get(Calendar.MONTH))
    println(lenient.get(Calendar.DAY_OF_MONTH))

    val date = Date(0L)
    println(date.time)
    date.time = 12345L
    println(date.time)
    println(date.getTime())

    println(Currency.getInstance("USD").symbol)
    println(Currency.getInstance("EUR").symbol)
    println(Currency.getInstance("GBP").symbol)
    println(Currency.getInstance("USD").currencyCode)
    println(Currency.getInstance("USD").getSymbol())
}
