// DIFF_WASM
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

@JvmInline
value class Counter(val raw: Long)

fun boxedCounter(value: Counter): Counter? = value

fun sameCounter(left: Counter?, right: Counter): Boolean = left == right

fun sameDoubleThroughAny(left: Double?, right: Any): Boolean = left == right

fun sameFloatThroughAny(left: Float?, right: Any): Boolean = left == right

fun main() {
    val missingLong: Long? = null
    val presentLong: Long? = 42L
    println(missingLong == null)
    println(missingLong != null)
    println(presentLong == null)
    println(presentLong != null)

    val missingDuration: Duration? = null
    val presentDuration: Duration? = 1.seconds
    println(missingDuration == null)
    println(missingDuration != null)
    println(presentDuration == null)
    println(presentDuration != null)
    println(Duration.parseOrNull("not-a-duration") == null)

    val minimumLong: Long? = Long.MIN_VALUE
    println(minimumLong == null)
    println(minimumLong != null)
    println(minimumLong == Long.MIN_VALUE)
    println(minimumLong!!)

    val highBitULong: ULong? = 9223372036854775808uL
    println(highBitULong == null)
    println(highBitULong != null)
    println(highBitULong == 9223372036854775808uL)
    println(highBitULong!!)

    val boxedCounter = boxedCounter(Counter(1L))
    println(boxedCounter == null)
    println(sameCounter(boxedCounter, Counter(1L)))
    println(sameCounter(boxedCounter, Counter(2L)))
    println(sameCounter(null, Counter(1L)))

    println(sameDoubleThroughAny(-0.0, 0.0))
    println(sameDoubleThroughAny(Double.NaN, Double.NaN))
    println(sameFloatThroughAny(-0.0f, 0.0f))
    println(sameFloatThroughAny(Float.NaN, Float.NaN))
}
