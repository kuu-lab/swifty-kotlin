// KUU-2010: value equality and Java-compatible hashing across construction paths.
import java.math.BigInteger

fun main() {
    val a = BigInteger.valueOf(7)
    val b = BigInteger.valueOf(7)
    println(a)
    println(b)
    println(a == b)
    println(a.hashCode() == b.hashCode())
    println(BigInteger.ONE.multiply(BigInteger.valueOf(7)) == b)

    val erased: Any = a
    println(erased == b)
    println(erased.hashCode() == b.hashCode())
    println(a.equals(null))
    println(a.equals("7"))
    println(a.equals(7L))
    println(a.equals(BigInteger.valueOf(8)))
    println(a.equals(BigInteger.valueOf(-7)))
    println(BigInteger.valueOf(-7) == BigInteger.valueOf(7).multiply(BigInteger.valueOf(-1)))
    println(BigInteger.valueOf(0) == BigInteger.valueOf(-7).multiply(BigInteger.valueOf(0)))
    println(BigInteger.ONE == BigInteger.valueOf(1))

    val large = BigInteger.valueOf(Long.MAX_VALUE).multiply(BigInteger.valueOf(2))
    val sameLarge = BigInteger.valueOf(2).multiply(BigInteger.valueOf(Long.MAX_VALUE))
    println(large)
    println(large == sameLarge)
    println(large.hashCode() == sameLarge.hashCode())
    val negativeLarge = large.multiply(BigInteger.valueOf(-1))
    println(negativeLarge == sameLarge.multiply(BigInteger.valueOf(-1)))
    println(negativeLarge.hashCode())

    val map = hashMapOf<BigInteger, String>()
    map[a] = "seven"
    println(map[b])
    map[b] = "updated"
    map[large] = "large"
    println(map.size)
    println(map[a])
    println(map[sameLarge])
    val set = hashSetOf(a, b, large, sameLarge, BigInteger.valueOf(-7), BigInteger.valueOf(0))
    println(set.size)
    println(set.contains(BigInteger.ONE.multiply(b)))
    println(set.contains(sameLarge))

    // Pin actual hash values, including word boundaries and signed overflow, to JDK.
    for (value in listOf(0L, 1L, -1L, 7L, -7L, 2147483648L, -2147483648L,
        4294967295L, 4294967296L, Long.MAX_VALUE, Long.MIN_VALUE)) {
        println(BigInteger.valueOf(value).hashCode())
    }
    println(large.hashCode())
    println(large.multiply(large).hashCode())
}
