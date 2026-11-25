// DIFF_JVM
import java.math.BigDecimal

var bigDecimalProp = BigDecimal("1.0")

fun main() {
    val a = BigDecimal("1.10")
    val b = BigDecimal("2.2")
    println(a + b)
    println(a - b)
    println(a * b)
    println(a / b)
    println(a % b)
    println(-a)
    println(a >= BigDecimal.ZERO)
    println(a == BigDecimal("1.10"))
    println(a.compareTo(b))
    val plusRef: (BigDecimal, BigDecimal) -> BigDecimal = BigDecimal::plus
    println(plusRef(a, b))
    val boundPlus: (BigDecimal) -> BigDecimal = a::plus
    println(boundPlus(b))
    println(BigDecimal(100))
    println(BigDecimal("1.2300").stripTrailingZeros().toPlainString())
    println(BigDecimal("123.45").precision())
    println(BigDecimal("1.2300").scale())

    var x = BigDecimal("1.0")
    println(x++)
    println(x)
    println(++x)
    println(x--)
    println(--x)

    println(bigDecimalProp++)
    println(bigDecimalProp)
    println(++bigDecimalProp)
    println(bigDecimalProp--)
    println(bigDecimalProp)

    val other = BigDecimal("100.0")
    val percentage = BigDecimal("10.0")
    println(other.times(percentage / BigDecimal(100)).abs())
}
