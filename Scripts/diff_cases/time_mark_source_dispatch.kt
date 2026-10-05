@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")
@file:OptIn(kotlin.time.ExperimentalTime::class)

import kotlin.time.AbstractDoubleTimeSource
import kotlin.time.AbstractLongTimeSource
import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.DurationUnit
import kotlin.time.TestTimeSource
import kotlin.time.TimeMark
import kotlin.time.TimeSource
import kotlin.time.measureTime
import kotlin.time.measureTimedValue

private class LongSource : AbstractLongTimeSource(DurationUnit.MILLISECONDS) {
    var reading: Long = 100L
    override fun read(): Long = reading
}

private class DoubleSource : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
    var reading: Double = 100.25
    override fun read(): Double = reading
}

private class CustomMark(var elapsed: Duration) : TimeMark {
    override fun elapsedNow(): Duration = elapsed
}

private fun checkMark(mark: ComparableTimeMark) {
    val erased: TimeMark = mark
    println(mark.elapsedNow() == 5.milliseconds)
    println(erased.elapsedNow() == 5.milliseconds)
    println(mark.hasPassedNow() && !mark.hasNotPassedNow())
    println(erased.hasPassedNow() && !erased.hasNotPassedNow())
    val future = mark + 10.milliseconds
    val past = mark - 10.milliseconds
    println(future.elapsedNow() == (-5).milliseconds)
    println(past.elapsedNow() == 15.milliseconds)
    println(future.hasNotPassedNow() && !future.hasPassedNow())
    println((future - mark) == 10.milliseconds)
    println((past - mark) == (-10).milliseconds)
    println(future > mark && past < mark)
    println((erased + 10.milliseconds).elapsedNow() == (-5).milliseconds)
    println((erased - 10.milliseconds).elapsedNow() == 15.milliseconds)
}

private fun checkDifferentSources(first: ComparableTimeMark, second: ComparableTimeMark) {
    try {
        first - second
        println(false)
    } catch (e: IllegalArgumentException) {
        println(true)
    }
    try {
        first.compareTo(second)
        println(false)
    } catch (e: IllegalArgumentException) {
        println(true)
    }
}

fun main() {
    val test = TestTimeSource()
    val start = test.markNow()
    println(start.elapsedNow() == Duration.ZERO)
    test += 5.milliseconds
    println(start.elapsedNow().inWholeMilliseconds == 5L)
    println((test.markNow() - start).inWholeMilliseconds == 5L)
    checkMark(start)
    val shifted = start + 10.milliseconds
    test += 10.milliseconds
    println(start.elapsedNow() == 15.milliseconds)
    println(shifted.elapsedNow() == 5.milliseconds)
    test += (-20).milliseconds
    println(start.elapsedNow() == (-5).milliseconds)
    println(start.hasNotPassedNow())
    val source: TimeSource = test
    println(source.measureTime { test += 7.milliseconds } == 7.milliseconds)
    val timed = source.measureTimedValue { test += 3.milliseconds; "result" }
    println(timed.value == "result" && timed.duration == 3.milliseconds)

    val longSource = LongSource()
    val longMark = longSource.markNow()
    longSource.reading = 105L
    checkMark(longMark)
    val doubleSource = DoubleSource()
    val doubleMark = doubleSource.markNow()
    doubleSource.reading = 105.25
    checkMark(doubleMark)
    checkDifferentSources(start, TestTimeSource().markNow())
    checkDifferentSources(longMark, LongSource().markNow())
    checkDifferentSources(doubleMark, DoubleSource().markNow())
    checkDifferentSources(longMark, doubleMark)

    val custom = CustomMark(5.milliseconds)
    val customErased: TimeMark = custom
    val adjusted = (customErased + 10.milliseconds) - 2.milliseconds
    println(adjusted.elapsedNow() == (-3).milliseconds)
    println(adjusted.hasNotPassedNow() && !adjusted.hasPassedNow())
    custom.elapsed = 9.milliseconds
    println(adjusted.elapsedNow() == 1.milliseconds)
    println(adjusted.hasPassedNow() && !adjusted.hasNotPassedNow())

    val monotonic: TimeSource.WithComparableMarks = TimeSource.Monotonic
    val monoMark = monotonic.markNow()
    val monoErased: TimeMark = monoMark
    println(monoMark.elapsedNow() >= Duration.ZERO)
    println(monoErased.elapsedNow() >= Duration.ZERO)
    println((monoMark + 1.days).hasNotPassedNow())
    println((monoErased - 1.days).hasPassedNow())
    println((monoMark + 1.days) - monoMark == 1.days)
    println(monoMark < monoMark + 1.days)
    checkDifferentSources(monoMark, start)
}
