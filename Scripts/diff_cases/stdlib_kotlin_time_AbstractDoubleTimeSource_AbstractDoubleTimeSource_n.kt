@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.time.AbstractDoubleTimeSource
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime

@OptIn(ExperimentalTime::class)
private class Probe : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
    override fun read(): Double = 12.5

    fun sourceUnit() = unit
}

@OptIn(ExperimentalTime::class)
fun main() {
    val probe = Probe()
    println(probe.sourceUnit())
    println(probe.markNow().elapsedNow().inWholeMilliseconds >= 0L)
}
