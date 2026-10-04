@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.time.AbstractDoubleTimeSource
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime

@OptIn(ExperimentalTime::class)
abstract class Probe : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS)

fun main() {}
