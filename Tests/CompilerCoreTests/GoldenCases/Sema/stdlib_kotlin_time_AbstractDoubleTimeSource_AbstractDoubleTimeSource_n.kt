@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.time.AbstractDoubleTimeSource
import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime

// KUU-1597 Sema owner: pin AbstractDoubleTimeSource override, inherited unit, and mark types; elapsed values stay in Scripts/diff_cases/stdlib_kotlin_time_AbstractDoubleTimeSource_AbstractDoubleTimeSource_n.kt.
@OptIn(ExperimentalTime::class)
private class Probe : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
    override fun read(): Double = 12.5

    fun sourceUnit(): DurationUnit = unit
}

@OptIn(ExperimentalTime::class)
fun main() {
    val probe = Probe()
    val sourceUnit: DurationUnit = probe.sourceUnit()
    val mark: ComparableTimeMark = probe.markNow()
    val elapsed: Duration = mark.elapsedNow()
    val wholeMilliseconds: Long = elapsed.inWholeMilliseconds
}
