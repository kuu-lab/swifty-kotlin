// DIFF_WASM
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

@JvmInline
value class Counter(val raw: Long)

@JvmInline
value class FloatCounter(val raw: Float)

@JvmInline
value class DoubleCounter(val raw: Double)

@JvmInline
value class NullableText(val value: String?)

class Link(var next: Link?, val delta: Long)

fun boxedCounter(value: Counter): Counter? = value

fun boxedCounterAny(value: Counter): Any = value

fun boxedFloatCounter(value: FloatCounter): Any = value

fun boxedDoubleCounter(value: DoubleCounter): Any = value

fun boxedLongMinimum(): Any = Long.MIN_VALUE

fun sameCounter(left: Counter?, right: Counter): Boolean = left == right

fun showNullableText(value: NullableText?) {
    println(value?.value)
}

fun sameDoubleThroughAny(left: Double?, right: Any): Boolean = left == right

fun sameFloatThroughAny(left: Float?, right: Any): Boolean = left == right

fun main() {
    val stableCounterBox: Any = boxedCounterAny(Counter(4096L))
    println(stableCounterBox.hashCode())
    boxedLongMinimum()
    println(stableCounterBox.hashCode())
    val addressCounterBox: Any = boxedCounterAny(Counter(4096L))
    val addressCounterBoxCopy: Any = boxedCounterAny(Counter(4096L))
    val minimumCounterForEquality: Any = boxedCounterAny(Counter(Long.MIN_VALUE))
    println(addressCounterBox == addressCounterBoxCopy)
    println(addressCounterBox == minimumCounterForEquality)

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

    showNullableText(NullableText("a"))
    showNullableText(NullableText(null))
    showNullableText(null)

    val counterBoxOne: Any = boxedCounterAny(Counter(1L))
    val counterBoxTwo: Any = boxedCounterAny(Counter(1L))
    println(counterBoxOne == counterBoxTwo)
    println(counterBoxOne.hashCode() == counterBoxTwo.hashCode())
    val floatCounterBoxOne: Any = boxedFloatCounter(FloatCounter(1.5f))
    val floatCounterBoxTwo: Any = boxedFloatCounter(FloatCounter(1.5f))
    println(floatCounterBoxOne == floatCounterBoxTwo)
    println(floatCounterBoxOne.hashCode() == floatCounterBoxTwo.hashCode())
    println(floatCounterBoxOne.hashCode())
    val doubleCounterBoxOne: Any = boxedDoubleCounter(DoubleCounter(1.5))
    val doubleCounterBoxTwo: Any = boxedDoubleCounter(DoubleCounter(1.5))
    println(doubleCounterBoxOne == doubleCounterBoxTwo)
    println(doubleCounterBoxOne.hashCode() == doubleCounterBoxTwo.hashCode())
    println(doubleCounterBoxOne.hashCode())
    val minimumCounterBox: Any = boxedCounterAny(Counter(Long.MIN_VALUE))
    val minimumCounterBoxCopy: Any = boxedCounterAny(Counter(Long.MIN_VALUE))
    println(minimumCounterBox == minimumCounterBoxCopy)
    println(minimumCounterBox.hashCode() == minimumCounterBoxCopy.hashCode())
    println(minimumCounterBox.hashCode())
    val wideCounterBox: Any = boxedCounterAny(Counter(4294967296L))
    println(wideCounterBox.hashCode())
    val longBoxOne = boxedLongMinimum()
    val longBoxTwo = boxedLongMinimum()
    println(longBoxOne == longBoxTwo)
    println(longBoxOne.hashCode() == longBoxTwo.hashCode())
    println(longBoxOne.hashCode())

    val selfLink = Link(null, -9030L)
    selfLink.next = selfLink
    val selfLinkAny: Any = selfLink
    selfLinkAny.hashCode()
    println("self-hash-ok")
    val firstLink: Any = Link(null, -9030L)
    val secondLink: Any = Link(null, -9030L)
    println(firstLink == secondLink)

    val minimumLongList = listOf<Long?>(Long.MIN_VALUE)
    println(minimumLongList.contains(null))
    println(minimumLongList.contains(Long.MIN_VALUE))

    println(sameDoubleThroughAny(-0.0, 0.0))
    println(sameDoubleThroughAny(Double.NaN, Double.NaN))
    println(sameFloatThroughAny(-0.0f, 0.0f))
    println(sameFloatThroughAny(Float.NaN, Float.NaN))
}
