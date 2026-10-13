// Minimal executable reproduction adapted from FactorialBigWithCache.kt at revision 1f89f062.
package other

import java.math.BigInteger

class FactorialBigWithCache {
    private val cache = hashMapOf<Int, BigInteger>()

    fun compute(number: Int): BigInteger {
        if (number <= 1) {
            return BigInteger.ONE
        }

        val cachedResult = cache[number]
        if (cachedResult != null) {
            return cachedResult
        }

        var result = BigInteger.ONE
        for (i in 2..number) {
            result = result.multiply(i.toBigInteger())
            cache[i] = result
        }
        return result
    }
}

fun main() {
    val factorial = FactorialBigWithCache()
    println(factorial.compute(0))
    println(factorial.compute(1))
    println(factorial.compute(-1))
    println(factorial.compute(30))
    val fifty = factorial.compute(50)
    println(fifty)
    println(fifty === factorial.compute(50))
    println(factorial.compute(70))
    println(BigInteger.valueOf(-3L).multiply(2.toBigInteger()))
    println(BigInteger.valueOf(0L).multiply(BigInteger.ONE))
}
