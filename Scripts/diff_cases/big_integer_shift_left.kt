// KUU-2012: independent of BigInteger.ZERO (KUU-2011).
// Upstream: FactorialAdvanced.kt at 1f89f062a056e24cc289ffdd0c6e23cadf8df887.
import java.math.BigInteger

fun main() {
    println(BigInteger.valueOf(3).shiftLeft(2))
    println(BigInteger.valueOf(-3).shiftLeft(2))
    println(BigInteger.valueOf(9).shiftLeft(-1))
    println(BigInteger.valueOf(7).shiftLeft(0))
    println(BigInteger.valueOf(-7).shiftLeft(0))
    println(BigInteger.valueOf(0).shiftLeft(100))
    println(BigInteger.valueOf(0).shiftLeft(Int.MAX_VALUE))
    println(BigInteger.valueOf(0).shiftLeft(Int.MIN_VALUE))
    println(BigInteger.ONE.shiftLeft(100))
    println(BigInteger.valueOf(-3).shiftLeft(100))
    println(BigInteger.valueOf(-9).shiftLeft(-1))
    println(BigInteger.valueOf(-8).shiftLeft(-3))
    println(BigInteger.valueOf(-7).shiftLeft(-3))
    println(BigInteger.valueOf(-19).shiftLeft(-1))
    println(BigInteger.valueOf(8).shiftLeft(-3))
    println(BigInteger.valueOf(-199).shiftLeft(-1))
    println(BigInteger.valueOf(9).shiftLeft(-100))
    println(BigInteger.valueOf(-9).shiftLeft(-100))
    println(BigInteger.valueOf(9).shiftLeft(Int.MIN_VALUE))
    println(BigInteger.valueOf(-9).shiftLeft(Int.MIN_VALUE))
    println(BigInteger.valueOf(Long.MIN_VALUE).shiftLeft(1))
    println(BigInteger.valueOf(Long.MIN_VALUE).shiftLeft(-63))
    println(BigInteger.valueOf(Long.MAX_VALUE).shiftLeft(65).shiftLeft(-65))
    println(BigInteger.ONE.shiftLeft(1024).shiftLeft(-1023))
    println(BigInteger.valueOf(-3).shiftLeft(1024).shiftLeft(-1025))
    println(BigInteger.valueOf(3).multiply(BigInteger.valueOf(-7)))
    println(BigInteger.valueOf(0).multiply(BigInteger.ONE))
    try {
        BigInteger.ONE.shiftLeft(Int.MAX_VALUE)
    } catch (_: ArithmeticException) {
        println("overflow")
    }
    try {
        BigInteger.valueOf(-3).shiftLeft(Int.MAX_VALUE - 1)
    } catch (_: ArithmeticException) {
        println("overflow")
    }
}
