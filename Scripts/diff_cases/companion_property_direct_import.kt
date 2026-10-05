import kotlin.Int.Companion.MAX_VALUE
import kotlin.Long.Companion.MIN_VALUE as longMin
import kotlin.time.Duration
import kotlin.time.Duration.Companion.INFINITE
import kotlin.time.Duration.Companion.ZERO as zeroDuration

fun main() {
    println(MAX_VALUE)
    println(longMin)
    println(INFINITE)
    println(zeroDuration)
    println(MAX_VALUE == Int.MAX_VALUE)
    println(INFINITE == Duration.INFINITE)
    println(zeroDuration == Duration.ZERO)
}
