// DIFF_JVM
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

fun main() {
    val negative = (-30).seconds
    println(negative.isNegative())
    println(negative.absoluteValue.inWholeSeconds)
    val positive = 10.seconds
    println(positive.isPositive())
    println(positive.isFinite())
    println(positive.isInfinite())
    val negativeInfinity = -Duration.INFINITE
    println(negativeInfinity.absoluteValue == Duration.INFINITE)
}
