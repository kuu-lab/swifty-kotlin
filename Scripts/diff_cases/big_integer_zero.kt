// KUU-2011: exact reproduction of the missing public ZERO constant.
import java.math.BigInteger
fun main() { println(BigInteger.ZERO); println(BigInteger.ZERO.multiply(BigInteger.ONE)) }
