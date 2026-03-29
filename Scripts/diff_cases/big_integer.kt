import java.math.BigInteger

fun main() {
    // BigInteger.valueOf(long)
    val a = BigInteger.valueOf(100)
    val b = BigInteger.valueOf(200)
    println("valueOf: ${a.toString()}")

    // BigInteger(String) constructor
    val c = BigInteger("12345678901234567890")
    println("fromString: ${c.toString()}")

    // add()
    val sum = a.add(b)
    println("add: ${sum.toString()}")

    // subtract()
    val diff = b.subtract(a)
    println("subtract: ${diff.toString()}")

    // multiply()
    val product = a.multiply(b)
    println("multiply: ${product.toString()}")

    // divide()
    val quotient = b.divide(a)
    println("divide: ${quotient.toString()}")

    // gcd()
    val x = BigInteger.valueOf(12)
    val y = BigInteger.valueOf(8)
    val g = x.gcd(y)
    println("gcd: ${g.toString()}")

    // abs()
    val neg = BigInteger.valueOf(-42)
    println("abs: ${neg.abs().toString()}")

    // pow()
    val base = BigInteger.valueOf(2)
    val powered = base.pow(10)
    println("pow: ${powered.toString()}")

    // toInt()
    val small = BigInteger.valueOf(42)
    println("toInt: ${small.toInt()}")

    // toLong()
    println("toLong: ${small.toLong()}")

    // toString()
    println("toString: ${small.toString()}")

    println("OK")
}
