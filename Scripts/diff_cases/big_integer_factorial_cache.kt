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
    // Preserve the upstream test order: populate 50, read cached 30, then extend to 70.
    val fifty = factorial.compute(50)
    println(fifty)
    println(factorial.compute(30))
    println(fifty === factorial.compute(50))
    println(factorial.compute(70))
    println(BigInteger.valueOf(-3L).multiply(2.toBigInteger()))
    println(BigInteger.valueOf(0L).multiply(BigInteger.ONE))

    // Preserve the upstream FactorialBigWithCacheTest operation order: 50, 30, 70.
    val upstream = FactorialBigWithCache()
    println(upstream.compute(50).toString() == "30414093201713378043612608166064768844377641568960512000000000000")
    println(upstream.compute(30).toString() == "265252859812191058636308480000000")
    println(upstream.compute(70).toString() == "11978571669969891796072783721689098736458938142546425857555362864628009582789845319680000000000000000")
    println(upstream.compute(50) == FactorialBigWithCache().compute(50))
    println(upstream.compute(70).hashCode() == FactorialBigWithCache().compute(70).hashCode())
}
