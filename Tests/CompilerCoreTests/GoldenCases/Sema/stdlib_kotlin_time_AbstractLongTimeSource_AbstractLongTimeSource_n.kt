@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.time.AbstractLongTimeSource
import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime

// KUU-1597 Sema owner: pin AbstractLongTimeSource override, inherited unit, and mark types; elapsed values stay in Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt.
@OptIn(ExperimentalTime::class)
private class Probe : AbstractLongTimeSource(DurationUnit.MILLISECONDS) {
    override fun read(): Long = 12L

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
