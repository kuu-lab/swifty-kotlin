// KUU-2026: digit products and carry must be part of the same addition expression.
import java.math.BigInteger

fun main() {
    println(BigInteger.ONE.multiply(BigInteger.valueOf(7)))
    println(BigInteger.valueOf(12).multiply(BigInteger.valueOf(34)))
    println(BigInteger.valueOf(0).multiply(BigInteger.valueOf(-7)))
    println(BigInteger.valueOf(-7).multiply(BigInteger.valueOf(0)))
    println(BigInteger.valueOf(-3).multiply(BigInteger.valueOf(2)))
    println(BigInteger.valueOf(3).multiply(BigInteger.valueOf(-2)))
    println(BigInteger.valueOf(-12).multiply(BigInteger.valueOf(-34)))
    println(BigInteger.valueOf(99).multiply(BigInteger.valueOf(99)))
    println(BigInteger.valueOf(999999999).multiply(BigInteger.valueOf(999999999)))
    println(BigInteger.valueOf(Long.MAX_VALUE).multiply(BigInteger.valueOf(2)))
    println(BigInteger.valueOf(Long.MIN_VALUE).multiply(BigInteger.valueOf(-1)))
    println(BigInteger.valueOf(Long.MAX_VALUE).multiply(BigInteger.valueOf(Long.MAX_VALUE)))
}
