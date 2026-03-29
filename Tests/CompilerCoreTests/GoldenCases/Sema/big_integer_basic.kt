import java.math.BigInteger

fun main() {
    val a = BigInteger.valueOf(100)
    val b = BigInteger.valueOf(200)
    val sum = a.add(b)
    val diff = b.subtract(a)
    val product = a.multiply(b)
    val quotient = b.divide(a)
    val g = a.gcd(b)
    val neg = BigInteger.valueOf(-42)
    val abs = neg.abs()
    val base = BigInteger.valueOf(2)
    val powered = base.pow(10)
    val s = BigInteger("12345")
    val i = s.toInt()
    val l = s.toLong()
    val str = s.toString()
}
