// KUU-2010: isolate the value contract from multiplication (tracked by KUU-2026).
import java.math.BigInteger

fun main() {
    val a = BigInteger.valueOf(7)
    val b = BigInteger.valueOf(7)
    val c: Any = BigInteger.valueOf(7)
    println(a == b)
    println(b.equals(c))
    println(c == a)
    println(a.hashCode() == b.hashCode())
    println(c.hashCode() == a.hashCode())
    println(a.equals(null))
    println(a.equals("7"))
    println(a.equals(7L))
    println(a.equals(BigInteger.valueOf(8)))
    println(a.equals(BigInteger.valueOf(-7)))
    println(BigInteger.valueOf(-7) == BigInteger.valueOf(-7))
    println(BigInteger.valueOf(0) == BigInteger.valueOf(0))
    println(BigInteger.ONE == BigInteger.valueOf(1))

    val map = hashMapOf(a to "seven")
    println(map[b])
    map[b] = "updated"
    println(map.size)
    println(map[a])
    val set = hashSetOf(a, b, BigInteger.valueOf(-7), BigInteger.valueOf(-7),
        BigInteger.valueOf(0), BigInteger.valueOf(0))
    println(set.size)
    println(set.contains(BigInteger.valueOf(-7)))
    println(set.contains(BigInteger.valueOf(0)))

    for (value in listOf(0L, 1L, -1L, 7L, -7L, 2147483648L, -2147483648L,
        4294967295L, 4294967296L, Long.MAX_VALUE, Long.MIN_VALUE)) {
        println(BigInteger.valueOf(value).hashCode())
    }
}
