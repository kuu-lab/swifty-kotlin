@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.time.AbstractLongTimeSource
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime

@OptIn(ExperimentalTime::class)
private class Probe : AbstractLongTimeSource(DurationUnit.MILLISECONDS) {
    override fun read(): Long = 12L

    fun sourceUnit() = unit
}

@OptIn(ExperimentalTime::class)
fun main() {
    val probe = Probe()
    println(probe.sourceUnit())
    println(probe.markNow().elapsedNow().inWholeMilliseconds >= 0L)
}
