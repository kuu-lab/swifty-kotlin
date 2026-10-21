// KUU-2755: public BigInteger(String) / BigInteger(String, Int) / byte-array ctors.
import java.math.BigInteger

fun main() {
    println(BigInteger("12345678901234567890"))
    println(BigInteger("+42"))
    println(BigInteger("-0042"))
    println(BigInteger("-0"))
    println(BigInteger("0007"))
    println(BigInteger("0"))
    println(BigInteger("ff", 16))
    println(BigInteger("FFFF", 16))
    println(BigInteger("-z", 36))
    println(BigInteger("101", 2))
    println(BigInteger("777", 8))

    println(BigInteger(byteArrayOf(0x01, 0x00)))
    println(BigInteger(byteArrayOf(-1)))
    println(BigInteger(byteArrayOf(-128, 0)))
    println(BigInteger(1, byteArrayOf(0x7f, -1)))
    println(BigInteger(-1, byteArrayOf(1)))
    println(BigInteger(1, byteArrayOf(0)))

    try { BigInteger("") } catch (e: NumberFormatException) { println("nfe-empty") }
    try { BigInteger("-") } catch (e: NumberFormatException) { println("nfe-sign") }
    try { BigInteger("+") } catch (e: NumberFormatException) { println("nfe-plus") }
    try { BigInteger("12a") } catch (e: NumberFormatException) { println("nfe-digit") }
    try { BigInteger("+-5") } catch (e: NumberFormatException) { println("nfe-embed") }
    try { BigInteger("1", 37) } catch (e: NumberFormatException) { println("nfe-radix") }
    try { BigInteger("1", 1) } catch (e: NumberFormatException) { println("nfe-radix-low") }
    try { BigInteger(byteArrayOf()) } catch (e: NumberFormatException) { println("nfe-bytes") }
    try { BigInteger(2, byteArrayOf(1)) } catch (e: NumberFormatException) { println("nfe-signum") }
    try { BigInteger(0, byteArrayOf(5)) } catch (e: NumberFormatException) { println("nfe-mismatch") }
}
