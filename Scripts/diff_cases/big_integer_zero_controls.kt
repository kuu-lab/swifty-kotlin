// KUU-2011: public BigInteger type and existing arithmetic remain compatible.
package consumer

import java.math.BigInteger

private fun render(value: BigInteger): String = value.toString()

fun main() {
    val zero: BigInteger = BigInteger.ZERO
    println(render(zero))
    println(render(BigInteger.valueOf(0L)))
    println(BigInteger.ONE.multiply(zero))
    println(zero.multiply(zero))
    println(zero.multiply(BigInteger.valueOf(-3L)))
    println(BigInteger.valueOf(-3L).multiply(zero))
    println(BigInteger.ONE)
    println(BigInteger.ONE.multiply(BigInteger.ONE))
    println(BigInteger.valueOf(-3L).multiply(BigInteger.valueOf(2L)))
    println(BigInteger.valueOf(12L).multiply(BigInteger.valueOf(34L)))
    println(render(zero))
}
