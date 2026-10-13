// KUU-1597 diff-only owner: keep the construction/runtime smoke here; inherited LongTimeSource type and mark resolution are owned by the focused Sema Golden stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt.
@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.time.AbstractLongTimeSource
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime

@OptIn(ExperimentalTime::class)
private class Probe : AbstractLongTimeSource(DurationUnit.MILLISECONDS) {
    override fun read(): Long = 12L
}

fun main() {
    println(Probe() !== null)
}
