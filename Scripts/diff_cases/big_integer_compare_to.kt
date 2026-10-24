// KUU-2822: BigInteger comparison must work directly and through PriorityQueue.
import java.math.BigInteger
import java.util.PriorityQueue

fun main() {
    println(BigInteger.valueOf(3).compareTo(BigInteger.ONE))
    println(BigInteger.valueOf(-3).compareTo(BigInteger.valueOf(-2)))
    println(BigInteger.valueOf(-1).compareTo(BigInteger.ZERO))
    println(BigInteger.ZERO.compareTo(BigInteger.ZERO))
    println(BigInteger("100000000000000000000").compareTo(BigInteger("99999999999999999999")))

    val queue = PriorityQueue<BigInteger>()
    queue.add(BigInteger.valueOf(3))
    queue.add(BigInteger.ONE)
    queue.add(BigInteger.valueOf(-2))
    queue.add(BigInteger.valueOf(3))
    while (queue.isNotEmpty()) println(queue.remove())
}
