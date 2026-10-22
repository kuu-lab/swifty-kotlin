// KUU-2755: arithmetic operators and core methods on java.math.BigInteger.
import java.math.BigInteger

fun main() {
    val a = BigInteger("12345678901234567890")
    val b = BigInteger.valueOf(98)

    println(a * b)
    println(a + b)
    println(a - b)
    println(b - a)
    println(-a)
    println(a / b)
    println(a % b)
    println(a.negate().remainder(b))
    println(a.divide(b.negate()))
    println(a > b)
    println(a < b)
    println(a >= b)
    println(a <= b)
    println(a.compareTo(b))
    println(b.compareTo(a))
    println(a.compareTo(a))

    var c = BigInteger.TEN
    c++
    println(c)
    c--
    println(c)
    c += b
    println(c)
    c -= b
    println(c)
    c *= b
    println(c)
    c /= b
    println(c)
    c %= b
    println(c)

    val (q, r) = a.divideAndRemainder(b)
    println(q)
    println(r)

    println(BigInteger.TWO)
    println(BigInteger.TEN)
    println(BigInteger("7").pow(3))
    println(BigInteger("2").pow(64))
    println(BigInteger("0").pow(0))
    println(BigInteger("12").gcd(BigInteger("18")))
    println(BigInteger("-12").gcd(BigInteger("18")))
    println(BigInteger("3").min(BigInteger("5")))
    println(BigInteger("3").max(BigInteger("5")))
    println(BigInteger("-9").abs())
    println(BigInteger("-9").signum())
    println(BigInteger.ZERO.signum())

    println(BigInteger("17").mod(BigInteger("5")))
    println(BigInteger("-17").mod(BigInteger("5")))
    println(BigInteger.ONE shl 5)
    println(BigInteger("256") shr 4)
    println(BigInteger("-256") shr 4)
    println(BigInteger("12") and BigInteger("10"))
    println(BigInteger("12") or BigInteger("10"))
    println(BigInteger("12") xor BigInteger("10"))
    println(BigInteger("5").inv())
    println(BigInteger("-5").inv())
    println(BigInteger("12").andNot(BigInteger("10")))

    println(BigInteger("4").modPow(BigInteger("13"), BigInteger("497")))
    println(BigInteger("3").modInverse(BigInteger("11")))
    println(BigInteger("-3").modInverse(BigInteger("11")))

    println(BigInteger("255").toString(16))
    println(BigInteger("-255").toString(16))
    println(BigInteger("35").toString(36))
    println(BigInteger("255").toByteArray().toList())
    println(BigInteger("-129").toByteArray().toList())
    println(BigInteger("12345678901234567890").toLong())
    println(BigInteger("18446744073709551617").toLong())
    println(BigInteger("-1").toLong())

    println(BigInteger("97").isProbablePrime(10))
    println(BigInteger("91").isProbablePrime(10))
    println(BigInteger("5").nextProbablePrime())
    println(BigInteger("144").sqrt())
    println(BigInteger("145").sqrt())

    println("255".toBigInteger())
    println("ff".toBigInteger(16))
    println("zz".toBigIntegerOrNull())
    println("12".toBigIntegerOrNull())
    println(42L.toBigInteger())
    println(BigInteger("5").toBigDecimal())

    try { BigInteger.ONE.divide(BigInteger.ZERO) } catch (e: ArithmeticException) { println("ae-div") }
    try { BigInteger.ONE.mod(BigInteger.ZERO) } catch (e: ArithmeticException) { println("ae-mod") }
    try { BigInteger("17").mod(BigInteger("-5")) } catch (e: ArithmeticException) { println("ae-modneg") }
    try { BigInteger.TWO.pow(-1) } catch (e: ArithmeticException) { println("ae-pow") }
    try { BigInteger("6").modInverse(BigInteger("3")) } catch (e: ArithmeticException) { println("ae-inv") }
    try { BigInteger("-1").sqrt() } catch (e: ArithmeticException) { println("ae-sqrt") }
    try { BigInteger.ONE.testBit(-1) } catch (e: ArithmeticException) { println("ae-testbit") }
}
